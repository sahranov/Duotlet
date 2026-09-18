#!/usr/bin/env python3
"""Generate the checked-in native app + WidgetKit extension project."""
from pathlib import Path
import hashlib, json, plistlib
root=Path(__file__).resolve().parent.parent
objects={}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key,isa,**attrs):
 i=uid(key);objects[i]={'isa':isa,**attrs};return i
def ref(path,typ): return add('file:'+path,'PBXFileReference',lastKnownFileType=typ,path=path,sourceTree='SOURCE_ROOT')
def build(key,r,**attrs):return add('build:'+key,'PBXBuildFile',fileRef=r,**attrs)
app_sources=sorted(root.glob('Sources/Duotlet/*.swift'))+list(root.glob('Sources/LidAngleKit/*.swift'))
shared=['Sources/Duotlet/ControlState.swift','Sources/Duotlet/SetDepthEffectIntent.swift','Sources/Duotlet/SettingsLanguage.swift']
control_sources=shared+['Sources/DuotletControl/DuotletControl.swift']
paths=sorted(set([str(p.relative_to(root)) for p in app_sources]+control_sources))
refs={p:ref(p,'sourcecode.swift') for p in paths}
children=list(refs.values())
resources=[]
for p,t in [('Sources/Duotlet/Resources/MenuBarIcon.pdf','image.pdf'),('Resources/AppIcon.icns','image.icns'),('Resources/PrivacyInfo.xcprivacy','text.xml'),('LICENSE','text'),('NOTICE','text')]:
 r=ref(p,t);children.append(r);resources.append(r)
loc=[]
for lang in ['en','ru','zh-Hans']:
 p=f'Sources/Duotlet/Resources/{lang}.lproj/Localizable.strings'
 loc.append(add('loc:'+lang,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=p,sourceTree='SOURCE_ROOT'))
localized=add('strings','PBXVariantGroup',children=loc,name='Localizable.strings',sourceTree='<group>');children.append(localized);resources.append(localized)
controlAssets=ref('Resources/Control/Assets.xcassets','folder.assetcatalog');children.append(controlAssets)
appProduct=add('product:app','PBXFileReference',explicitFileType='wrapper.application',path='Duotlet.app',sourceTree='BUILT_PRODUCTS_DIR')
extProduct=add('product:extension','PBXFileReference',explicitFileType='wrapper.app-extension',path='DuotletControl.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[appProduct,extProduct],name='Products',sourceTree='<group>')
children.append(products)
group=add('root','PBXGroup',children=children,sourceTree='<group>')

def configurations(key,settings):
 ids=[]
 for name in ['Debug','Release']:
  values=dict(settings)
  values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if name=='Debug' else 'dwarf-with-dsym')
  ids.append(add(key+name,'XCBuildConfiguration',buildSettings=values,name=name))
 return add(key+'configs','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
versionInfo=plistlib.loads((root/'Resources/Info.plist').read_bytes())
common={'SDKROOT':'macosx','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':versionInfo['CFBundleVersion'],'MARKETING_VERSION':versionInfo['CFBundleShortVersionString'],'DUOTLET_APP_GROUP':'group.app.duotlet.shared','DEVELOPMENT_TEAM':'','MACOSX_DEPLOYMENT_TARGET':'14.0'}
projectConfigs=configurations('project',common)
appSettings={'PRODUCT_NAME':'Duotlet','PRODUCT_BUNDLE_IDENTIFIER':'app.duotlet.Duotlet','INFOPLIST_FILE':'Resources/Xcode-Info.plist','CODE_SIGN_ENTITLEMENTS':'Resources/Xcode-Duotlet.entitlements','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],'ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'YES','SKIP_INSTALL':'NO'}
extSettings={'PRODUCT_NAME':'DuotletControl','PRODUCT_BUNDLE_IDENTIFIER':'app.duotlet.Duotlet.Control','INFOPLIST_FILE':'Resources/Control/Xcode-Info.plist','CODE_SIGN_ENTITLEMENTS':'Resources/Control/Xcode-DuotletControl.entitlements','MACOSX_DEPLOYMENT_TARGET':'26.0','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','ENABLE_APP_SANDBOX':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks']}
appCompile=add('app:sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[build('app:'+str(p.relative_to(root)),refs[str(p.relative_to(root))]) for p in app_sources],runOnlyForDeploymentPostprocessing=0)
extCompile=add('ext:sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[build('ext:'+p,refs[p]) for p in control_sources],runOnlyForDeploymentPostprocessing=0)
appRes=add('app:resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[build('appres:'+r,r) for r in resources],runOnlyForDeploymentPostprocessing=0)
extRes=add('ext:resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[build('extres',localized),build('extprivacy',uid('file:Resources/PrivacyInfo.xcprivacy')),build('extassets',controlAssets)],runOnlyForDeploymentPostprocessing=0)
embed=add('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[build('embed',extProduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
proxy=add('proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=uid('extension'),remoteInfo='DuotletControl')
dep=add('dependency','PBXTargetDependency',target=uid('extension'),targetProxy=proxy)
telemetryPackage=add('telemetry:package','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/TelemetryDeck/SwiftSDK',requirement={'kind':'upToNextMajorVersion','minimumVersion':'2.14.2'})
telemetryProduct=add('telemetry:product','XCSwiftPackageProductDependency',package=telemetryPackage,productName='TelemetryDeck')
telemetryBuild=add('telemetry:build','PBXBuildFile',productRef=telemetryProduct)
frameworks=add('app:frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[telemetryBuild],runOnlyForDeploymentPostprocessing=0)
appTarget=add('app','PBXNativeTarget',buildConfigurationList=configurations('app',appSettings),packageProductDependencies=[telemetryProduct],buildPhases=[appCompile,frameworks,appRes,embed],buildRules=[],dependencies=[dep],name='Duotlet',productName='Duotlet',productReference=appProduct,productType='com.apple.product-type.application')
extTarget=add('extension','PBXNativeTarget',buildConfigurationList=configurations('extension',extSettings),buildPhases=[extCompile,extRes],buildRules=[],dependencies=[],name='DuotletControl',productName='DuotletControl',productReference=extProduct,productType='com.apple.product-type.app-extension')
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2600','TargetAttributes':{appTarget:{'CreatedOnToolsVersion':'26.0'},extTarget:{'CreatedOnToolsVersion':'26.0'}}},buildConfigurationList=projectConfigs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ru','zh-Hans','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[appTarget,extTarget],packageReferences=[telemetryPackage])
def write(v,depth=0):
 indent='\t'*depth
 if isinstance(v,dict):return '{\n'+''.join(indent+'\t'+json.dumps(str(k))+' = '+write(x,depth+1)+';\n' for k,x in v.items())+indent+'}'
 if isinstance(v,list):return '(\n'+''.join(indent+'\t'+write(x,depth+1)+',\n' for x in v)+indent+')'
 if isinstance(v,int):return str(v)
 return json.dumps(v,ensure_ascii=False)
p=root/'Duotlet.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+write({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
for original,dest in [('Resources/Info.plist','Resources/Xcode-Info.plist'),('Resources/Control/Info.plist','Resources/Control/Xcode-Info.plist')]:
 d=plistlib.loads((root/original).read_bytes());d.update(CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',DuotletAppGroup='$(DUOTLET_APP_GROUP)')
 if 'DuotletContainingApp' in d:d['DuotletContainingApp']='app.duotlet.Duotlet'
 plistlib.dump(d,open(root/dest,'wb'))
for p in ['Resources/Xcode-Duotlet.entitlements','Resources/Control/Xcode-DuotletControl.entitlements']:
 d={'com.apple.security.app-sandbox':True,'com.apple.security.application-groups':['$(DUOTLET_APP_GROUP)']}
 if p.startswith('Resources/Xcode'):
  d['com.apple.security.device.usb']=True
  d['com.apple.security.network.client']=True
 plistlib.dump(d,open(root/p,'wb'))
scheme=root/'Duotlet.xcodeproj/xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'Duotlet.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="Duotlet.app" BlueprintName="Duotlet" ReferencedContainer="container:Duotlet.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="Duotlet.app" BlueprintName="Duotlet" ReferencedContainer="container:Duotlet.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
