#!/usr/bin/env python3
"""只使用标准库生成可直接打开的 Xcode 工程，无需安装项目生成工具。"""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
ids = lambda s: hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects = []
def obj(name, value):
    objects.append(f'{ids(name)} = {{ {value} }};')
    return ids(name)
sources=[]; resources=[]; children=[]
for p in sorted((root/'EverFrame').rglob('*')):
    if not p.is_file() or p.suffix not in ['.swift','.html','.js','.css','.xcprivacy']: continue
    path=p.relative_to(root).as_posix()
    typ='sourcecode.swift' if p.suffix=='.swift' else 'text'
    ref=obj(path, f'isa = PBXFileReference; lastKnownFileType = {typ}; path = "{path}"; sourceTree = SOURCE_ROOT;')
    build=obj(path+'build', f'isa = PBXBuildFile; fileRef = {ref};')
    children.append(ref)
    (sources if p.suffix=='.swift' else resources).append(build)
config=obj('config','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Product.xcconfig; sourceTree = SOURCE_ROOT;')
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = EverFrame.app; sourceTree = BUILT_PRODUCTS_DIR;')
children += [config,product]
group=obj('group',f'isa = PBXGroup; children = ({",".join(children)},); sourceTree = "<group>";')
src=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(sources)},); runOnlyForDeploymentPostprocessing = 0;')
res=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)}); runOnlyForDeploymentPostprocessing = 0;')
framework=obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for scope in ['project','target']:
    configs=[]
    for mode in ['Debug','Release']:
        settings='SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; '
        if scope=='target': settings += 'SWIFT_EMIT_LOC_STRINGS = YES; '
        if mode=='Debug': settings += 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;'
        else: settings += 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        configs.append(obj(scope+mode,f'isa = XCBuildConfiguration; baseConfigurationReference = {config}; buildSettings = {{ {settings} }}; name = {mode};'))
    obj(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {ids("targetconfigs")}; buildPhases = ({src},{framework},{res},); buildRules = (); dependencies = (); name = EverFrame; productName = EverFrame; productReference = {product}; productType = "com.apple.product-type.application";')
project=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2650; }}; buildConfigurationList = {ids("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; knownRegions = ("zh-Hans",en,Base,); mainGroup = {group}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
folder=root/'EverFrame.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
scheme=folder/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
(scheme/'EverFrame.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2650" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="EverFrame.app" BlueprintName="EverFrame" ReferencedContainer="container:EverFrame.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="EverFrame.app" BlueprintName="EverFrame" ReferencedContainer="container:EverFrame.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('已生成 EverFrame.xcodeproj')
