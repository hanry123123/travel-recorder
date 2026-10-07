#!/usr/bin/env python3
"""Inspect the built payload, including binary deployment versions and dependencies."""
import hashlib
import json
import pathlib
import plistlib
import struct
import zipfile
import argparse
from package_checks import check_payload_file

root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output-dir',type=pathlib.Path,default=root/'artifacts/device')
args=parser.parse_args()
out=args.output_dir
receipt=json.loads((out/'receipt.json').read_text())
ipa=out/('TravelRecorder-'+receipt['version']+'.ipa')
checks=[]
def require(condition, label):
    if not condition: raise RuntimeError(label)
    checks.append(label)

def version(value): return [value>>16, (value>>8)&255, value&255]
def macho(data):
    magic=struct.unpack_from('>I',data)[0]
    if magic in (0xcafebabe,0xcafebabf):
        wide=magic==0xcafebabf
        count=struct.unpack_from('>I',data,4)[0]
        for i in range(count):
            offset=8+i*(32 if wide else 20)
            cpu=struct.unpack_from('>I',data,offset)[0]
            start,size=struct.unpack_from('>QQ' if wide else '>II',data,offset+8)
            if cpu==0x0100000c: return macho(data[start:start+size])
        raise RuntimeError('No ARM64 slice in embedded library')
    require(data[:4]==b'\xcf\xfa\xed\xfe','Mach-O 64-bit little endian')
    _,cpu,_,filetype,count,_,_,_=struct.unpack_from('<8I',data)
    require(cpu==0x0100000c,'ARM64 architecture')
    cursor=32; minimum=None; sdk=None; platform=None; dependencies=[]; rpaths=[]
    for _ in range(count):
        cmd,size=struct.unpack_from('<II',data,cursor)
        require(size>=8 and cursor+size<=len(data),'Valid Mach-O load command')
        if cmd==0x32:
            platform,minimum,sdk=struct.unpack_from('<III',data,cursor+8)
        elif cmd==0x25:
            minimum,sdk=struct.unpack_from('<II',data,cursor+8); platform=2
        elif cmd in (0xc,0x80000018,0x8000001f):
            name_offset=struct.unpack_from('<I',data,cursor+8)[0]
            name=data[cursor+name_offset:cursor+size].split(b'\0')[0].decode()
            dependencies.append({'name':name,'weak':cmd==0x80000018})
        elif cmd==0x8000001c:
            name_offset=struct.unpack_from('<I',data,cursor+8)[0]
            rpaths.append(data[cursor+name_offset:cursor+size].split(b'\0')[0].decode())
        cursor+=size
    require(minimum is not None and platform==2,'iOS device platform metadata')
    return {'minimum_os':version(minimum),'sdk':version(sdk),'dependencies':dependencies,'rpaths':rpaths,'filetype':filetype}

with zipfile.ZipFile(ipa) as archive:
    require(archive.testzip() is None,'ZIP integrity')
    prefix='Payload/TravelRecorder.app/'
    names=set(archive.namelist())
    require(len(names)==len(archive.namelist()),'No duplicate ZIP entries')
    for name in sorted(names):
        check_payload_file(name, archive.read(name))
    require(True,'Every payload file scanned: no dSYM or unsupported Mach-O types')
    require(all(name.startswith(prefix) and '..' not in pathlib.PurePosixPath(name).parts for name in names),'Payload contains only expected app files')
    info=plistlib.loads(archive.read(prefix+'Info.plist'))
    require(info['CFBundleIdentifier']=='com.aluba.travelrecorder','Stable bundle identifier')
    require(info['CFBundleShortVersionString']==receipt['version'],'Version matches receipt')
    require(info['MinimumOSVersion']=='14.0','Info.plist minimum iOS 14.0')
    require(info['CFBundleExecutable']=='TravelRecorder','Executable name matches payload')
    require(info['UIBackgroundModes']==['location'],'Background location capability')
    require(bool(info['NSLocationWhenInUseUsageDescription']) and bool(info['NSPhotoLibraryUsageDescription']),'Location and photo permission explanations')
    require(info['UIDeviceFamily']==[1],'iPhone device family')
    require('UILaunchScreen' in info,'iOS 14 launch screen declaration')
    require(info.get('UIApplicationSceneManifest',{}).get('UIApplicationSupportsMultipleScenes') is False,'SwiftUI scene lifecycle enabled with a single window')
    require(prefix+'AppIcon60x60@2x.png' in names and prefix+'AppIcon60x60@3x.png' in names,'Required iPhone icons packaged')
    require(bool((archive.getinfo(prefix+'TravelRecorder').external_attr>>16)&0o111),'Executable permission retained')
    executable=macho(archive.read(prefix+'TravelRecorder'))
    require(executable['filetype']==2,'Main binary is MH_EXECUTE')
    require(executable['minimum_os']==[14,0,0],'Actual executable minimum OS is iOS 14.0')
    require(executable['sdk']==[18,2,0],'Executable linked with the selected iOS 18.2 SDK metadata')
    require('@executable_path/Frameworks' in executable['rpaths'],'Embedded runtime search path')
    libraries={}
    for name in names:
        if name.endswith('.dylib'):
            parsed=macho(archive.read(name))
            require(parsed['filetype']==6,'Embedded runtime is MH_DYLIB')
            require(parsed['minimum_os']<=[14,0,0],'Embedded runtime supports iOS 14')
            libraries[pathlib.PurePosixPath(name).name]=parsed
    for binary in [executable]+list(libraries.values()):
        for dependency in binary['dependencies']:
            if dependency['name'].startswith('@rpath/'):
                require(pathlib.PurePosixPath(dependency['name']).name in libraries,'Referenced embedded runtime is present')
    require(prefix+'_CodeSignature/CodeResources' in names,'Ad hoc bundle signature present for installation')
receipt=json.loads((out/'receipt.json').read_text())
require(receipt['ipa_sha256']==hashlib.sha256(ipa.read_bytes()).hexdigest(),'Package SHA-256 matches build receipt')
require(receipt['input_manifest_sha256']==hashlib.sha256((out/'build-input.SHA256SUMS').read_bytes()).hexdigest(),'Build receipt binds its input manifest')
result={'status':'PASS','checks':len(checks),'ipa_sha256':receipt['ipa_sha256'],'executable':executable,'embedded_libraries':libraries,'device_tested':False}
(out/'package-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('PACKAGE AUDIT PASS:',len(checks),'checks; embedded libraries:',', '.join(libraries))
