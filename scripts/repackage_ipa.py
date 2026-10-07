#!/usr/bin/env python3
"""Repackage a verified build without recompiling unchanged Swift sources."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import zipfile

from package_checks import check_payload_directory

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--base-ipa', type=pathlib.Path, required=True)
parser.add_argument('--base-sha256', required=True)
parser.add_argument('--base-input-manifest', type=pathlib.Path, required=True)
parser.add_argument('--output-dir', type=pathlib.Path, required=True)
args = parser.parse_args()
out = args.output_dir.resolve()
if out.exists():
    raise SystemExit('Output directory must be new: ' + str(out))
sha = lambda data: hashlib.sha256(data).hexdigest()
if sha(args.base_ipa.read_bytes()) != args.base_sha256:
    raise SystemExit('Base IPA SHA-256 mismatch')
base_inputs = dict((name, digest) for digest, name in
                   (line.split('  ', 1) for line in args.base_input_manifest.read_text().splitlines()))
sources = sorted(p.relative_to(root).as_posix() for p in (root/'Sources').rglob('*.swift'))
if set(sources) != {name for name in base_inputs if name.startswith('Sources/') and name.endswith('.swift')}:
    raise SystemExit('Swift source file set changed; compile a fresh build')
for name in sources:
    if sha((root/name).read_bytes()) != base_inputs[name]:
        raise SystemExit('Swift source changed; compile a fresh build: ' + name)
out.mkdir(parents=True)
removed = []
prefix = 'Payload/TravelRecorder.app/'
with zipfile.ZipFile(args.base_ipa) as archive:
    if archive.testzip() is not None:
        raise SystemExit('Base ZIP corrupt')
    if len(archive.namelist()) != len(set(archive.namelist())):
        raise SystemExit('Duplicate ZIP entries')
    for item in archive.infolist():
        name = item.filename
        parts = pathlib.PurePosixPath(name).parts
        if not name.startswith(prefix) or '..' in parts or item.is_dir():
            raise SystemExit('Unexpected input member: ' + name)
        if any(part.lower().endswith('.dsym') for part in parts):
            removed.append(name)
            # Keep separate diagnostic symbols for this exact executable.
            target = out/'symbols'/pathlib.Path(*parts[2:])
        elif '_CodeSignature' in parts:
            continue  # Bundle seal must be regenerated after changing resources.
        else:
            target = out/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(item))
        target.chmod((item.external_attr >> 16) & 0o777)
app = out/'Payload/TravelRecorder.app'
info = plistlib.loads((app/'Info.plist').read_bytes())
source_info = plistlib.loads((root/'Resources/Info.plist').read_bytes())
# This route allows only version changes to the source Info.plist.
for key, value in source_info.items():
    if key not in ('CFBundleExecutable', 'CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion'):
        if info.get(key) != value:
            raise SystemExit('Non-version Info.plist change; compile a fresh build: ' + key)
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    info[key] = source_info[key]
(app/'Info.plist').write_bytes(plistlib.dumps(info))
original_main_sha = sha((app/'TravelRecorder').read_bytes())
check_payload_directory(out/'Payload')
with (out/'codesign.log').open('w') as log:
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(app)],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
check_payload_directory(out/'Payload')
version = info['CFBundleShortVersionString']
ipa = out/('TravelRecorder-' + version + '.ipa')
with zipfile.ZipFile(ipa, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((out/'Payload').rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(out))
shutil.copy2(root/'source.SHA256SUMS', out/'build-input.SHA256SUMS')
shutil.copy2(args.base_input_manifest, out/'base-compile-input.SHA256SUMS')
receipt = {'version': version, 'build': info['CFBundleVersion'],
           'bundle_id': info['CFBundleIdentifier'], 'minimum_os': info['MinimumOSVersion'],
           'architecture': 'arm64', 'build_method': 'Local packaging-only repair; reuse verified 1.0.0 compiled binaries',
           'base_ipa_sha256': args.base_sha256, 'base_main_before_resigning_sha256': original_main_sha,
           'base_input_manifest_sha256': sha(args.base_input_manifest.read_bytes()),
           'unchanged_swift_sources': sources, 'removed_debug_entries': removed,
           'ipa_sha256': sha(ipa.read_bytes()),
           'input_manifest_sha256': sha((out/'build-input.SHA256SUMS').read_bytes()),
           'device_tested': False}
(out/'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
