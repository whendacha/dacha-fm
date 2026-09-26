#!/usr/bin/env python3
"""Generate a deterministic Xcode project without third-party tooling."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def obj(name, value):
    key = ident(name)
    objects[key] = value
    return key

def array(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

sources, resources, refs = [], [], []
for path in sorted((ROOT / 'NearFM').rglob('*')):
    if not path.is_file() or '.xcassets' in str(path):
        continue
    rel = path.relative_to(ROOT).as_posix()
    if path.suffix == '.swift':
        kind, phase = 'sourcecode.swift', sources
    elif path.suffix in ('.wav', '.xcprivacy'):
        kind, phase = ('audio.wav' if path.suffix == '.wav' else 'text.xml'), resources
    else:
        continue
    ref = obj('file:' + rel, f'{{isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(rel)}; sourceTree = "<group>"; }}')
    refs.append(ref)
    phase.append(obj('build:' + rel, f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))

asset = obj('assets', '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = NearFM/Resources/Assets.xcassets; sourceTree = "<group>"; }')
refs.append(asset)
resources.append(obj('assets-build', f'{{isa = PBXBuildFile; fileRef = {asset}; }}'))
product = obj('product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = DachaFM.app; sourceTree = BUILT_PRODUCTS_DIR; }')
product_group = obj('products', f'{{isa = PBXGroup; children = {array([product])}; name = Products; sourceTree = "<group>"; }}')
main_group = obj('main-group', f'{{isa = PBXGroup; children = {array(refs + [product_group])}; sourceTree = "<group>"; }}')
package = obj('package', '{isa = XCLocalSwiftPackageReference; relativePath = Packages/NearFMCore; }')
package_product = obj('package-product', f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = NearFMCore; }}')
package_build = obj('package-build', f'{{isa = PBXBuildFile; productRef = {package_product}; }}')
source_phase = obj('sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0; }}')
resource_phase = obj('resources', f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0; }}')
framework_phase = obj('frameworks', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array([package_build])}; runOnlyForDeploymentPostprocessing = 0; }}')

def settings(values):
    return '{' + ''.join(f'{key} = {quote(value)}; ' for key, value in values.items()) + '}'

project_configs, target_configs = [], []
for configuration in ('Debug', 'Release'):
    debug = configuration == 'Debug'
    project_configs.append(obj('project-' + configuration, '{isa = XCBuildConfiguration; name = ' + configuration + '; buildSettings = ' + settings({
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'SDKROOT': 'iphoneos',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if debug else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)' if debug else '$(inherited)',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if debug else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY': 'YES' if debug else 'NO', 'ONLY_ACTIVE_ARCH': 'YES' if debug else 'NO',
    }) + '; }'))
    config_ref = obj('config-' + configuration, '{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/' + configuration + '.xcconfig; sourceTree = "<group>"; }')
    target_configs.append(obj('target-' + configuration, '{isa = XCBuildConfiguration; name = ' + configuration + '; baseConfigurationReference = ' + config_ref + '; buildSettings = ' + settings({
        'PRODUCT_NAME': 'DachaFM', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.whendacha.dachafm',
        'INFOPLIST_FILE': 'NearFM/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
        'CODE_SIGN_ENTITLEMENTS': 'NearFM/NearFM.entitlements', 'CODE_SIGN_STYLE': 'Automatic',
        'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0.0',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
        'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
        'SWIFT_EMIT_LOC_STRINGS': 'YES',
    }) + '; }'))
project_config_list = obj('project-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
target_config_list = obj('target-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
target = obj('target', f'{{isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; buildPhases = {array([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = (); name = NearFM; packageProductDependencies = {array([package_product])}; productName = DachaFM; productReference = {product}; productType = "com.apple.product-type.application"; }}')
test_file = obj('uitest-file', '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NearFMUITests/ListenerUITests.swift; sourceTree = "<group>"; }')
test_build = obj('uitest-build', f'{{isa = PBXBuildFile; fileRef = {test_file}; }}')
test_sources = obj('uitest-sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array([test_build])}; runOnlyForDeploymentPostprocessing = 0; }}')
test_product = obj('uitest-product', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = NearFMUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
test_configs = []
for configuration in ('Debug', 'Release'):
    test_configs.append(obj('uitest-' + configuration, '{isa = XCBuildConfiguration; name = ' + configuration + '; buildSettings = ' + settings({
        'PRODUCT_NAME': 'NearFMUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.whendacha.dachafm.uitests',
        'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'NearFM', 'SWIFT_VERSION': '5.0',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'TARGETED_DEVICE_FAMILY': '1', 'CODE_SIGN_STYLE': 'Automatic',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    }) + '; }'))
test_config_list = obj('uitest-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(test_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
dependency = obj('uitest-dependency', f'{{isa = PBXTargetDependency; target = {target}; }}')
test_target = obj('uitest-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {test_config_list}; buildPhases = {array([test_sources])}; buildRules = (); dependencies = {array([dependency])}; name = NearFMUITests; productName = NearFMUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing"; }}')
objects[main_group] = f'{{isa = PBXGroup; children = {array(refs + [test_file, product_group])}; sourceTree = "<group>"; }}'
objects[product_group] = f'{{isa = PBXGroup; children = {array([product, test_product])}; name = Products; sourceTree = "<group>"; }}'
project = obj('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 26.0; }}; {test_target} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, Base); mainGroup = {main_group}; packageReferences = {array([package])}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array([target, test_target])}; }}')
directory = ROOT / 'NearFM.xcodeproj'
directory.mkdir(exist_ok=True)
(directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {value};' for key, value in objects.items()) + f'\n}}; rootObject = {project}; }}\n')
schemes = directory / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DachaFM.app" BlueprintName="NearFM" ReferencedContainer="container:NearFM.xcodeproj"/>'
(schemes / 'NearFM.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="NearFMUITests.xctest" BlueprintName="NearFMUITests" ReferencedContainer="container:NearFM.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {directory} with {len(sources)} Swift files')
