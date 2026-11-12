#!/usr/bin/env python3
"""Reproduce the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
from hashlib import sha1
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def identifier(name): return sha1(name.encode()).hexdigest()[:24].upper()
def add(key_name, isa, **values):
    key = identifier(key_name); objects[key] = dict(isa=isa, **values); return key

def file(path, kind):
    return add('file:'+path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')
def group(name, children): return add('group:'+name, 'PBXGroup', name=name, children=children, sourceTree='<group>')
def build_file(target, reference): return add('build:'+target+reference, 'PBXBuildFile', fileRef=reference)

project_id = identifier('project')
app_id, widget_id, test_id = [identifier('target:'+s) for s in ['HeadQuarter','HeadQuarterWidgets','HeadQuarterTests']]
paths = sorted(str(p.relative_to(ROOT)) for p in ROOT.glob('**/*.swift') if '.build' not in p.parts and str(p.relative_to(ROOT)).startswith(('HeadQuarter/', 'Shared/', 'HeadQuarterWidgets/')))
refs = {p:file(p,'sourcecode.swift') for p in paths}
app_sources = [p for p in paths if p.startswith(('HeadQuarter/', 'Shared/'))]
widget_sources = [p for p in paths if p.startswith('HeadQuarterWidgets/') or p in ['Shared/Domain.swift','Shared/OperationAttributes.swift']]
test_sources = sorted(str(p.relative_to(ROOT)) for p in ROOT.glob('HeadQuarterTests/*.swift'))
refs.update({p:file(p,'sourcecode.swift') for p in test_sources})
resources = {}
for target in ['HeadQuarter','HeadQuarterWidgets']:
    paths_for_target=[target+'/PrivacyInfo.xcprivacy'] + (['HeadQuarter/Assets.xcassets'] if target=='HeadQuarter' else [])
    resources[target] = [file(p,'folder.assetcatalog' if p.endswith('xcassets') else 'text.xml') for p in paths_for_target]
configs = []
for target in ['HeadQuarter','HeadQuarterWidgets']:
    configs.extend([file(target+'/Info.plist','text.plist.xml'), file(target+'/'+target+'.entitlements','text.plist.entitlements')])
products = {name:add('product:'+name,'PBXFileReference',explicitFileType=kind,includeInIndex=0,path=name+suffix,sourceTree='BUILT_PRODUCTS_DIR') for name,kind,suffix in [('HeadQuarter','wrapper.application','.app'),('HeadQuarterWidgets','wrapper.app-extension','.appex'),('HeadQuarterTests','wrapper.cfbundle','.xctest')]}
shared_group=group('Shared',[r for p,r in refs.items() if p.startswith('Shared/')])
app_group=group('iPhone App',[r for p,r in refs.items() if p.startswith('HeadQuarter/')]+resources['HeadQuarter']+configs[:2])
widget_group=group('Widgets and Live Activities',[r for p,r in refs.items() if p.startswith('HeadQuarterWidgets/')]+resources['HeadQuarterWidgets']+configs[2:])
test_group=group('Tests',[refs[p] for p in test_sources])
products_group=group('Products',list(products.values()))
main_group=group('Head Quarter',[app_group,shared_group,widget_group,test_group,products_group])

def phase(target, kind, files):
    return add('phase:'+target+kind,kind,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
def config_list(name, settings):
    ids=[]
    for mode in ['Debug','Release']:
        values=dict(settings)
        if name=='Project':
            values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym')
            if mode=='Debug': values.update(ENABLE_TESTABILITY='YES',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)',GCC_PREPROCESSOR_DEFINITIONS=['DEBUG=1','$(inherited)'])
        ids.append(add('config:'+name+mode,'XCBuildConfiguration',name=mode,buildSettings=values))
    return add('config-list:'+name,'XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

base = dict(CLANG_ENABLE_MODULES='YES',CLANG_ENABLE_OBJC_ARC='YES',CLANG_WARN_DOCUMENTATION_COMMENTS='YES',CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER='YES',GCC_C_LANGUAGE_STANDARD='gnu17',SWIFT_VERSION='5.0',IPHONEOS_DEPLOYMENT_TARGET='17.0',SDKROOT='iphoneos',SWIFT_EMIT_LOC_STRINGS='YES',ENABLE_USER_SCRIPT_SANDBOXING='YES')
project_configs=config_list('Project',base)
common=dict(CODE_SIGN_STYLE='Automatic',CURRENT_PROJECT_VERSION='1',MARKETING_VERSION='1.0',TARGETED_DEVICE_FAMILY='1',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'])
app_settings=dict(common,PRODUCT_BUNDLE_IDENTIFIER='com.headquarter.app',PRODUCT_NAME='$(TARGET_NAME)',INFOPLIST_FILE='HeadQuarter/Info.plist',CODE_SIGN_ENTITLEMENTS='HeadQuarter/HeadQuarter.entitlements',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME='AccentColor')
widget_settings=dict(common,PRODUCT_BUNDLE_IDENTIFIER='com.headquarter.app.widgets',PRODUCT_NAME='$(TARGET_NAME)',INFOPLIST_FILE='HeadQuarterWidgets/Info.plist',CODE_SIGN_ENTITLEMENTS='HeadQuarterWidgets/HeadQuarterWidgets.entitlements',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'])
test_settings=dict(common,PRODUCT_BUNDLE_IDENTIFIER='com.headquarter.app.tests',PRODUCT_NAME='$(TARGET_NAME)',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/HeadQuarter.app/HeadQuarter',BUNDLE_LOADER='$(TEST_HOST)')
# Dependency ensures the widget is built before embedding.
widget_proxy=add('proxy:widgets','PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=widget_id,remoteInfo='HeadQuarterWidgets')
widget_dependency=add('dependency:widgets','PBXTargetDependency',target=widget_id,targetProxy=widget_proxy)
app_proxy=add('proxy:app','PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=app_id,remoteInfo='HeadQuarter')
app_dependency=add('dependency:app','PBXTargetDependency',target=app_id,targetProxy=app_proxy)
embed_build=add('embed:widget','PBXBuildFile',fileRef=products['HeadQuarterWidgets'],settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed=add('phase:embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed_build],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
for name,sources,settings,dependencies in [('HeadQuarter',app_sources,app_settings,[widget_dependency]),('HeadQuarterWidgets',widget_sources,widget_settings,[]),('HeadQuarterTests',test_sources,test_settings,[app_dependency])]:
    phases=[phase(name,'PBXSourcesBuildPhase',[build_file(name,refs[p]) for p in sources]),phase(name,'PBXFrameworksBuildPhase',[]),phase(name,'PBXResourcesBuildPhase',[build_file(name,r) for r in resources.get(name,[])])]
    if name=='HeadQuarter': phases.append(embed)
    product_type={'HeadQuarter':'com.apple.product-type.application','HeadQuarterWidgets':'com.apple.product-type.app-extension','HeadQuarterTests':'com.apple.product-type.bundle.unit-test'}[name]
    add('target:'+name,'PBXNativeTarget',buildConfigurationList=config_list(name,settings),buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=products[name],productType=product_type)
# Modern single-target watchOS SwiftUI companion.
watch_id = identifier('target:HeadQuarterWatch')
watch_paths = ['HeadQuarterWatch/HeadQuarterWatchApp.swift', 'Shared/Domain.swift', 'Shared/WatchPayload.swift']
watch_refs = {path: refs.get(path) or file(path, 'sourcecode.swift') for path in watch_paths}
watch_product = add('product:HeadQuarterWatch','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='HeadQuarterWatch.app',sourceTree='BUILT_PRODUCTS_DIR')
objects[products_group]['children'].append(watch_product)
objects[main_group]['children'].append(group('Apple Watch',list(watch_refs.values())))
watch_settings = dict(common,SDKROOT='watchos',SUPPORTED_PLATFORMS='watchos watchsimulator',WATCHOS_DEPLOYMENT_TARGET='10.0',TARGETED_DEVICE_FAMILY='4',PRODUCT_BUNDLE_IDENTIFIER='com.headquarter.app.watchkitapp',PRODUCT_NAME='$(TARGET_NAME)',INFOPLIST_FILE='HeadQuarterWatch/Info.plist',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'])
add('target:HeadQuarterWatch','PBXNativeTarget',buildConfigurationList=config_list('HeadQuarterWatch',watch_settings),buildPhases=[phase('HeadQuarterWatch','PBXSourcesBuildPhase',[build_file('HeadQuarterWatch',ref) for ref in watch_refs.values()]),phase('HeadQuarterWatch','PBXFrameworksBuildPhase',[]),phase('HeadQuarterWatch','PBXResourcesBuildPhase',[build_file('HeadQuarterWatch',file('HeadQuarterWatch/PrivacyInfo.xcprivacy','text.xml'))])],buildRules=[],dependencies=[],name='HeadQuarterWatch',productName='HeadQuarterWatch',productReference=watch_product,productType='com.apple.product-type.application')
watch_proxy=add('proxy:watch','PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=watch_id,remoteInfo='HeadQuarterWatch')
objects[app_id]['dependencies'].append(add('dependency:watch','PBXTargetDependency',target=watch_id,targetProxy=watch_proxy))
watch_embed_file=add('embed:watch','PBXBuildFile',fileRef=watch_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
objects[app_id]['buildPhases'].append(add('phase:embed-watch','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='$(CONTENTS_FOLDER_PATH)/Watch',dstSubfolderSpec=16,files=[watch_embed_file],name='Embed Watch Content',runOnlyForDeploymentPostprocessing=0))
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1620','TargetAttributes':{app_id:{'CreatedOnToolsVersion':'16.2','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}},widget_id:{'CreatedOnToolsVersion':'16.2','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}},test_id:{'CreatedOnToolsVersion':'16.2','TestTargetID':app_id}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=products_group,projectDirPath='',projectRoot='',targets=[app_id,widget_id,test_id,watch_id])
def serialize(value,depth=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+' = '+serialize(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(depth+1)+serialize(v,depth+1)+',\n' for v in value)+'\t'*depth+')'
    if isinstance(value,int):return str(value)
    return json.dumps(value)
project=ROOT/'HeadQuarter.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project_id))+'\n')
# Shared schemes are committed so command-line builds do not depend on a user's Xcode state.
from xml.sax.saxutils import escape
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def ref(name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier("target:"+name)}" BuildableName="{name}{".app" if name=="HeadQuarter" else ".appex" if name=="HeadQuarterWidgets" else ".app" if name=="HeadQuarterWatch" else ".xctest"}" BlueprintName="{name}" ReferencedContainer="container:HeadQuarter.xcodeproj"/>'
(schemes/'HeadQuarter.xcscheme').write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('HeadQuarter')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref('HeadQuarterTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('HeadQuarter')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('HeadQuarter')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>""")
(schemes/'HeadQuarterWidgets.xcscheme').write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('HeadQuarterWidgets')}</BuildActionEntry></BuildActionEntries></BuildAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>""")
print(f'Generated {len(objects)} objects, {len(app_sources)} app sources, {len(widget_sources)} widget sources, {len(test_sources)} test files')

(schemes/'HeadQuarterWatch.xcscheme').write_text(f'<Scheme LastUpgradeVersion="1620" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref("HeadQuarterWatch")}</BuildActionEntry></BuildActionEntries></BuildAction><AnalyzeAction buildConfiguration="Debug"/></Scheme>')
