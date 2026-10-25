#!/usr/bin/env python3
"""Run real UIKit drawing/AVFoundation export on the installed Mac Catalyst runtime."""
from pathlib import Path
import subprocess,os
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/share-fixture'
out.mkdir(parents=True,exist_ok=True)
for name in ['module-cache','tmp','output']:(out/name).mkdir(exist_ok=True)
dev=Path('/Applications/Xcode.app/Contents/Developer')
sdk=dev/'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
support=sdk/'System/iOSSupport'
sources=sorted(p for p in (root/'Sources').rglob('*.swift') if p.name!='TravelRecorderApp.swift')
cmd=[str(dev/'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'),'-swift-version','5','-O','-target','x86_64-apple-ios14.0-macabi','-sdk',str(sdk),'-F',str(support/'System/Library/Frameworks'),'-I',str(support/'usr/include'),'-L',str(support/'usr/lib'),'-module-cache-path',str(out/'module-cache')]+list(map(str,sources))+[str(root/'Tests/SharePreview/main.swift'),'-o',str(out/'share-fixture')]
env=dict(os.environ,DEVELOPER_DIR=str(dev),TMPDIR=str(out/'tmp'))
with (out/'compile.log').open('w') as log:subprocess.run(cmd,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'run.log').open('w') as log:subprocess.run([str(out/'share-fixture'),str(out/'output')],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=240)
print((out/'run.log').read_text())
