#!/usr/bin/env python3
"""Reproduce the reported ldid failure, then re-sign a copy of the fixed IPA."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile
import zipfile

from package_checks import check_payload_file

parser = argparse.ArgumentParser()
parser.add_argument('--old-ipa', type=pathlib.Path, required=True)
parser.add_argument('--new-ipa', type=pathlib.Path, required=True)
parser.add_argument('--ldid', type=pathlib.Path, required=True)
parser.add_argument('--output-dir', type=pathlib.Path, required=True)
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
ldid = str(args.ldid.resolve())
logs = []


def run(step, flags, expected):
    result = subprocess.run([ldid] + flags, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    logs.append({'step': step, 'exit_code': result.returncode, 'output': result.stdout})
    if result.returncode != expected:
        raise RuntimeError(str(logs[-1]))
    return result.stdout


with tempfile.TemporaryDirectory(prefix='signing-regression-', dir=args.output_dir) as temporary:
    temp = pathlib.Path(temporary)
    for label, ipa in [('old', args.old_ipa), ('new', args.new_ipa)]:
        with zipfile.ZipFile(ipa) as archive:
            # Only extract known, bounded app paths; the signing copy is disposable.
            for item in archive.infolist():
                name = item.filename
                if not name.startswith('Payload/TravelRecorder.app/') or '..' in pathlib.PurePosixPath(name).parts:
                    raise ValueError('Unexpected archive member: ' + name)
                target = temp/label/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(item))
                target.chmod((item.external_attr >> 16) & 0o777)
            gate_errors = []
            for name in archive.namelist():
                try:
                    check_payload_file(name, archive.read(name))
                except ValueError as error:
                    gate_errors.append(str(error))
            if label == 'old':
                assert gate_errors and all('Debug symbols' in error for error in gate_errors)
                debug_name = next(n for n in archive.namelist() if '/DWARF/' in n)
                # Renaming the debug binary must not evade the content-based gate.
                try:
                    check_payload_file('Payload/TravelRecorder.app/renamed.bin', archive.read(debug_name))
                except ValueError as error:
                    assert 'Unsupported Mach-O type [10]' in str(error)
                else:
                    raise AssertionError('Renamed MH_DSYM escaped release gate')
            else:
                assert not gate_errors, gate_errors
            logs.append({'step': label + '_payload_gate', 'rejections': gate_errors})
        app = temp/label/'Payload/TravelRecorder.app'
        if label == 'new':
            verified = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            logs.append({'step': 'new_before_ldid_codesign_verify', 'exit_code': verified.returncode, 'output': verified.stdout})
            assert verified.returncode == 0, verified.stdout
        run(label + '_main', ['-S', str(app/'TravelRecorder')], 0)
        message = run(label + '_bundle', ['-s', str(app)], 1 if label == 'old' else 0)
        if label == 'old':
            assert 'Unsupported Mach-O type' in message
        else:
            for binary in [app/'TravelRecorder'] + sorted((app/'Frameworks').glob('*.dylib')):
                hashes = run('new_ldid_cdhash_' + binary.name, ['-h', str(binary)], 0)
                assert 'CDHash=' in hashes, hashes
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {'status': 'PASS', 'old_ipa_sha256': sha(args.old_ipa), 'new_ipa_sha256': sha(args.new_ipa),
          'ldid_sha256': sha(args.ldid), 'ldid_release': 'ProcursusTeam/ldid v2.1.5-procursus7 macOS x86_64',
          'results': logs, 'device_tested': False,
          'scope': 'Host ldid signing regression; phone installation and CoreTrust stage still pending'}
(args.output_dir/'signing-regression.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
