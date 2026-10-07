#!/usr/bin/env python3
"""Generate a dependency-free Xcode project and geometric app icon."""
import hashlib
import json
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

def icon(size):
    # Native geometric artwork: blue field and a winding white route.
    scale = 3 if size < 200 else 1
    n = size * scale
    route = [(0.28, 0.73), (0.25, 0.64), (0.32, 0.52), (0.49, 0.51), (0.64, 0.55), (0.72, 0.45), (0.67, 0.30)]
    pixels = bytearray()
    for y in range(size):
        pixels.append(0)
        for x in range(size):
            color = [0, 0, 0]
            for sy in range(scale):
                for sx in range(scale):
                    px, py = (x*scale+sx+0.5)/n, (y*scale+sy+0.5)/n
                    distance = 1.0
                    for a, b in zip(route, route[1:]):
                        dx, dy = b[0]-a[0], b[1]-a[1]
                        t = max(0, min(1, ((px-a[0])*dx+(py-a[1])*dy)/(dx*dx+dy*dy)))
                        distance = min(distance, ((px-a[0]-t*dx)**2+(py-a[1]-t*dy)**2)**0.5)
                    endpoint = min(((px-a[0])**2+(py-a[1])**2)**0.5 for a in (route[0], route[-1]))
                    rgb = (255, 255, 255) if distance < .034 or endpoint < .066 else (int(15+12*py), int(125-32*py), int(245-18*py))
                    color = [v+c for v,c in zip(color,rgb)]
            pixels.extend(int(v/(scale*scale)) for v in color)
    def chunk(name, data):
        return struct.pack('>I', len(data))+name+data+struct.pack('>I', zlib.crc32(name+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(pixels),9))+chunk(b'IEND',b'')

def main():
    assets = ROOT/'Resources/Assets.xcassets'
    appicon = assets/'AppIcon.appiconset'
    appicon.mkdir(parents=True, exist_ok=True)
    (assets/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}}))
    entries = []
    for base in [20,29,40,60]:
        for scale in [2,3]:
            name=f'icon-{base}@{scale}x.png'
            (appicon/name).write_bytes(icon(base*scale))
            entries.append({'idiom':'iphone','size':f'{base}x{base}','scale':f'{scale}x','filename':name})
    (appicon/'icon-1024.png').write_bytes(icon(1024))
    entries.append({'idiom':'ios-marketing','size':'1024x1024','scale':'1x','filename':'icon-1024.png'})
    (appicon/'Contents.json').write_text(json.dumps({'images':entries,'info':{'version':1,'author':'xcode'}},indent=2))
    sources=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Sources').rglob('*.swift'))
    objects=[]
    def obj(key, content): objects.append(f'{ident(key)} = {{ {content} }};')
    for path in sources:
        obj(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = "<group>";')
        obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ident(path)};')
    obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = "<group>";')
    obj('build:assets',f'isa = PBXBuildFile; fileRef = {ident("assets")};')
    obj('notices', 'isa = PBXFileReference; lastKnownFileType = text; path = docs/THIRD-PARTY.md; sourceTree = "<group>";')
    obj('build:notices', f'isa = PBXBuildFile; fileRef = {ident("notices")};')
    obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = TravelRecorder.app; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('products', f'isa = PBXGroup; children = ({ident("product")},); name = Products; sourceTree = "<group>";')
    obj('group', 'isa = PBXGroup; children = ('+','.join(ident(p) for p in sources)+f',{ident("assets")},{ident("notices")},{ident("products")},); sourceTree = "<group>";')
    obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(ident('build:'+p) for p in sources)+',); runOnlyForDeploymentPostprocessing = 0;')
    obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ident("build:assets")},{ident("build:notices")},); runOnlyForDeploymentPostprocessing = 0;')
    obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    for configuration in ['Debug','Release']:
        project_settings={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_STRICT_CONCURRENCY':'minimal','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','ENABLE_BITCODE':'NO'}
        target_settings={'PRODUCT_BUNDLE_IDENTIFIER':'com.aluba.travelrecorder','PRODUCT_NAME':'TravelRecorder','INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','TARGETED_DEVICE_FAMILY':'1','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGNING_ALLOWED':'NO','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SWIFT_EMIT_LOC_STRINGS':'NO'}
        for group, settings in [('project',project_settings),('target',target_settings)]:
            obj(group+configuration,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{key} = {quoted(value)};' for key,value in settings.items())+'}; name = '+configuration+';')
    for group in ['project','target']:
        obj(group+'configs',f'isa = XCConfigurationList; buildConfigurations = ({ident(group+"Debug")},{ident(group+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {ident("targetconfigs")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")},); buildRules = (); dependencies = (); name = TravelRecorder; productName = TravelRecorder; productReference = {ident("product")}; productType = "com.apple.product-type.application";')
    obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1620; }}; buildConfigurationList = {ident("projectconfigs")}; compatibilityVersion = "Xcode 12.0"; developmentRegion = zh_CN; knownRegions = (zh_CN,en,Base,); mainGroup = {ident("group")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")},);')
    project=ROOT/'TravelRecorder.xcodeproj'
    project.mkdir(exist_ok=True)
    (project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 54; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {ident("project")}; }}\n')
    schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
    (schemes/'TravelRecorder.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target')}" BuildableName="TravelRecorder.app" BlueprintName="TravelRecorder" ReferencedContainer="container:TravelRecorder.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target')}" BuildableName="TravelRecorder.app" BlueprintName="TravelRecorder" ReferencedContainer="container:TravelRecorder.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
    print(f'Generated project with {len(sources)} Swift sources and app icon.')

if __name__=='__main__': main()
