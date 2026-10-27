from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
base=root/'ios'
def uid(text): return hashlib.sha256(text.encode()).hexdigest()[:24].upper()
files=sorted((base/'PillCheck').rglob('*.swift'))
resources=[base/'PillCheck/Resources/Assets.xcassets']
objects=[]
def add(key,body): objects.append(f'{uid(key)} = {{ {body} }};')
for file in files+resources:
 p=file.relative_to(base).as_posix()
 t='sourcecode.swift' if file.suffix=='.swift' else 'folder.assetcatalog' if file.suffix=='.xcassets' else 'image.png'
 add(p,f'isa = PBXFileReference; lastKnownFileType = {t}; path = "{p}"; sourceTree = SOURCE_ROOT;')
 add('build'+p,f'isa = PBXBuildFile; fileRef = {uid(p)};')
add('app','isa = PBXFileReference; explicitFileType = wrapper.application; path = PillCheck.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(uid('build'+p.relative_to(base).as_posix()) for p in files)+'); runOnlyForDeploymentPostprocessing = 0;')
add('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(uid('build'+p.relative_to(base).as_posix()) for p in resources)+'); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('products',f'isa = PBXGroup; children = ({uid("app")}); name = Products; sourceTree = "<group>";')
add('main','isa = PBXGroup; children = ('+','.join(uid(p.relative_to(base).as_posix()) for p in files+resources)+','+uid('products')+'); sourceTree = "<group>";')
for config in ['Debug','Release']:
 settings='CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; '
 settings+='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ' if config=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; '
 add('project'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};')
 app='PRODUCT_BUNDLE_IDENTIFIER = com.himanshugarg.pillcheck; PRODUCT_NAME = PillCheck; INFOPLIST_FILE = PillCheck/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = "1,2"; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ENABLE_USER_SCRIPT_SANDBOXING = YES; SWIFT_EMIT_LOC_STRINGS = YES; SUPPORTS_MACCATALYST = NO; '
 add('target'+config,f'isa = XCBuildConfiguration; buildSettings = {{ {app} }}; name = {config};')
for kind in ['project','target']:
 add(kind+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(kind+"Debug")},{uid(kind+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = PillCheck; productName = PillCheck; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
project='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n'
(base/'PillCheck.xcodeproj/project.pbxproj').write_text(project)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="PillCheck.app" BlueprintName="PillCheck" ReferencedContainer="container:PillCheck.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="PillCheck.app" BlueprintName="PillCheck" ReferencedContainer="container:PillCheck.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(base/'PillCheck.xcodeproj/xcshareddata/xcschemes/PillCheck.xcscheme').write_text(scheme)
print(f'Generated Xcode project with {len(files)} Swift files')
