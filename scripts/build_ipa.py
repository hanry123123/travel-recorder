#!/usr/bin/env python3
"""Compile using the installed Xcode compiler/SDK; no simulator or global setup writes."""
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import time
import zipfile
from package_checks import check_payload_directory

root = pathlib.Path(__file__).resolve().parents[1]
out = root/'artifacts/device'
app = out/'Payload/TravelRecorder.app'
if app.exists():
    shutil.rmtree(app)  # Generated payload only; prevent stale build files entering IPA.
app.mkdir(parents=True, exist_ok=True)
compiled = out/'compiled'; compiled.mkdir(exist_ok=True)
tmp = out/'tmp'; tmp.mkdir(exist_ok=True)
cache = out/'module-cache'; cache.mkdir(exist_ok=True)
developer = pathlib.Path('/Applications/Xcode.app/Contents/Developer')
toolchain = developer/'Toolchains/XcodeDefault.xctoolchain/usr/bin'
sdk = developer/'Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk'
env = dict(os.environ, DEVELOPER_DIR=str(developer), SDKROOT=str(sdk), TMPDIR=str(tmp))
sources = sorted((root/'Sources').rglob('*.swift'))
command = [str(toolchain/'swiftc'), '-swift-version','5','-parse-as-library','-O','-g','-whole-module-optimization','-target','arm64-apple-ios14.0','-sdk',str(sdk),'-module-cache-path',str(cache),'-module-name','TravelRecorder','-Xlinker','-rpath','-Xlinker','@executable_path/Frameworks','-Xlinker','-platform_version','-Xlinker','ios','-Xlinker','14.0','-Xlinker','18.2']
# swiftc -g can emit an adjacent .dSYM automatically: compile outside Payload.
command += [str(p) for p in sources] + ['-o',str(compiled/'TravelRecorder')]
started = time.time()
shutil.copyfile(root/'source.SHA256SUMS',out/'build-input.SHA256SUMS')
with (out/'build.log').open('w') as log:
    log.write('COMMAND '+json.dumps(command)+'\n'); log.flush()
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env, cwd=root)
if result.returncode:
    print((out/'build.log').read_text())
    raise SystemExit(result.returncode)
shutil.copy2(compiled/'TravelRecorder', app/'TravelRecorder')
info = plistlib.loads((root/'Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='TravelRecorder',CFBundleIdentifier='com.aluba.travelrecorder',MinimumOSVersion='14.0',CFBundleSupportedPlatforms=['iPhoneOS'],UIDeviceFamily=[1])
info['CFBundleIcons'] = {'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60'],'UIPrerenderedIcon':False}}
for scale in [2,3]: shutil.copyfile(root/f'Resources/Assets.xcassets/AppIcon.appiconset/icon-60@{scale}x.png', app/f'AppIcon60x60@{scale}x.png')
(app/'Info.plist').write_bytes(plistlib.dumps(info))
(app/'PkgInfo').write_bytes(b'APPL????')
shutil.copyfile(root/'docs/THIRD-PARTY.md', app/'ThirdPartyNotices.txt')
# Bundle Xcode's compatibility runtimes. SwiftUI has indirect weak concurrency
# references even though the app itself does not use async/await.
frameworks=app/'Frameworks'; frameworks.mkdir(exist_ok=True)
with (out/'runtime-copy.log').open('w') as log:
    subprocess.run([str(toolchain/'swift-stdlib-tool'),'--copy','--verbose','--scan-executable',str(app/'TravelRecorder'),'--platform','iphoneos','--destination',str(frameworks)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
for library in sorted(frameworks.glob('*.dylib')):
    archs=subprocess.check_output(['/usr/bin/lipo','-archs',str(library)],env=env,text=True).split()
    if len(archs)>1:
        thin=library.with_suffix('.thin')
        subprocess.run(['/usr/bin/lipo',str(library),'-thin','arm64','-output',str(thin)],env=env,check=True)
        thin.replace(library)
# Ad hoc signing requires no Apple account. TrollStore re-signs on installation.
check_payload_directory(out/'Payload')
with (out/'codesign.log').open('w') as log:
    for target in sorted(frameworks.glob('*.dylib'))+[app]:
        subprocess.run(['/usr/bin/codesign','--force','--sign','-','--timestamp=none',str(target)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',str(app)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'dsym.log').open('w') as log:
    subprocess.run([str(toolchain/'dsymutil'),str(app/'TravelRecorder'),'-o',str(out/'TravelRecorder.app.dSYM')],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
version = info['CFBundleShortVersionString']
ipa = out/('TravelRecorder-' + version + '.ipa')
check_payload_directory(out/'Payload')
with zipfile.ZipFile(ipa,'w',compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((out/'Payload').rglob('*')):
        if path.is_file(): archive.write(path,path.relative_to(out))
receipt={'version':version,'bundle_id':info['CFBundleIdentifier'],'minimum_os':info['MinimumOSVersion'],'architecture':'arm64','build_seconds':round(time.time()-started,2),'ipa_sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'input_manifest_sha256':hashlib.sha256((out/'build-input.SHA256SUMS').read_bytes()).hexdigest(),'build_method':'Xcode 16.2 swiftc and iPhoneOS SDK, direct native build','device_tested':False}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
