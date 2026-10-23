"""Dependency-free deterministic Xcode project generator. Run after adding source files."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "AkiChat.xcodeproj"

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

def generate():
    objects = []
    def obj(name, body):
        objects.append(f"\t\t{uid(name)} = {{ {body} }};")
        return uid(name)
    def array(items):
        return "(" + ", ".join(items) + ",)" if items else "()"
    source_refs, test_refs, source_builds, test_builds, resources = [], [], [], [], []
    ui_refs, ui_builds = [], []
    for folder, refs, builds in [("AkiChat", source_refs, source_builds), ("AkiChatTests", test_refs, test_builds), ("AkiChatUITests", ui_refs, ui_builds)]:
        for path in sorted((ROOT / folder).rglob("*.swift"), key=lambda p: p.relative_to(ROOT).as_posix()):
            name = path.relative_to(ROOT).as_posix()
            ref = obj("ref:" + name, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(name)}; sourceTree = {q('<group>')};")
            refs.append(ref)
            builds.append(obj("build:" + name, f"isa = PBXBuildFile; fileRef = {ref};"))
    for name, typ in [("AkiChat/Assets.xcassets", "folder.assetcatalog"), ("AkiChat/LICENSE.txt", "text")]:
        ref = obj("ref:" + name, f"isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(name)}; sourceTree = {q('<group>')};")
        source_refs.append(ref)
        resources.append(obj("build:" + name, f"isa = PBXBuildFile; fileRef = {ref};"))
    app = obj("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = AkiChat.app; sourceTree = BUILT_PRODUCTS_DIR;')
    tests = obj("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AkiChatTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    ui_tests = obj("ui-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AkiChatUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    products = obj("products", f"isa = PBXGroup; children = {array([app, tests, ui_tests])}; name = Products; sourceTree = {q('<group>')};")
    group = obj("main-group", f"isa = PBXGroup; children = {array(source_refs + test_refs + ui_refs + [products])}; sourceTree = {q('<group>')};")
    for name, kind, files in [("app-sources", "PBXSourcesBuildPhase", source_builds), ("test-sources", "PBXSourcesBuildPhase", test_builds), ("ui-sources", "PBXSourcesBuildPhase", ui_builds), ("ui-frameworks", "PBXFrameworksBuildPhase", []), ("app-resources", "PBXResourcesBuildPhase", resources), ("app-frameworks", "PBXFrameworksBuildPhase", []), ("test-frameworks", "PBXFrameworksBuildPhase", [])]:
        obj(name, f"isa = {kind}; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;")
    common = {"IPHONEOS_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "SDKROOT": "iphoneos", "TARGETED_DEVICE_FAMILY": "1", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE"}
    for owner in ["project", "app", "tests", "ui-tests"]:
        configs = []
        for configuration in ["Debug", "Release"]:
            settings = dict(common)
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym" if configuration == "Release" else "dwarf", "SWIFT_OPTIMIZATION_LEVEL": "-O" if configuration == "Release" else "-Onone"})
            if configuration == "Debug": settings.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES"})
            if owner == "app":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "com.akisenn.akichat", "PRODUCT_NAME": "AkiChat", "INFOPLIST_FILE": "AkiChat/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGNING_ALLOWED": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks", "SWIFT_EMIT_LOC_STRINGS": "NO"})
            if owner == "tests":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "com.akisenn.akichat.tests", "PRODUCT_NAME": "AkiChatTests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/AkiChat.app/AkiChat", "BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGNING_ALLOWED": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
            if owner == "ui-tests":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "com.akisenn.akichat.uitests", "PRODUCT_NAME": "AkiChatUITests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "AkiChat", "CODE_SIGNING_ALLOWED": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
            body = " ".join(f"{k} = {q(v)};" for k, v in sorted(settings.items()))
            configs.append(obj(owner + configuration, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {configuration};"))
        obj(owner + "-configs", f"isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    obj("proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('app')}; remoteInfo = AkiChat;")
    obj("dependency", f"isa = PBXTargetDependency; target = {uid('app')}; targetProxy = {uid('proxy')};")
    obj("app", f"isa = PBXNativeTarget; buildConfigurationList = {uid('app-configs')}; buildPhases = {array([uid('app-sources'), uid('app-frameworks'), uid('app-resources')])}; buildRules = (); dependencies = (); name = AkiChat; productName = AkiChat; productReference = {app}; productType = {q('com.apple.product-type.application')};")
    obj("tests", f"isa = PBXNativeTarget; buildConfigurationList = {uid('tests-configs')}; buildPhases = {array([uid('test-sources'), uid('test-frameworks')])}; buildRules = (); dependencies = {array([uid('dependency')])}; name = AkiChatTests; productName = AkiChatTests; productReference = {tests}; productType = {q('com.apple.product-type.bundle.unit-test')};")
    obj("ui-tests", f"isa = PBXNativeTarget; buildConfigurationList = {uid('ui-tests-configs')}; buildPhases = {array([uid('ui-sources'), uid('ui-frameworks')])}; buildRules = (); dependencies = {array([uid('dependency')])}; name = AkiChatUITests; productName = AkiChatUITests; productReference = {ui_tests}; productType = {q('com.apple.product-type.bundle.ui-testing')};")
    obj("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1620; }}; buildConfigurationList = {uid('project-configs')}; compatibilityVersion = {q('Xcode 14.0')}; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = {q('')}; projectRoot = {q('')}; targets = {array([uid('app'), uid('tests'), uid('ui-tests')])};")
    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n", encoding="utf-8")
    scheme = ET.Element("Scheme", LastUpgradeVersion="1620", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    def reference(parent, name, product, label):
        return ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=uid(name), BuildableName=product, BlueprintName=label, ReferencedContainer="container:AkiChat.xcodeproj")
    reference(entry, "app", "AkiChat.app", "AkiChat")
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    reference(ET.SubElement(testables, "TestableReference", skipped="NO"), "tests", "AkiChatTests.xctest", "AkiChatTests")
    reference(ET.SubElement(testables, "TestableReference", skipped="NO"), "ui-tests", "AkiChatUITests.xctest", "AkiChatUITests")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "app", "AkiChat.app", "AkiChat")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "app", "AkiChat.app", "AkiChat")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    path = PROJECT / "xcshareddata/xcschemes/AkiChat.xcscheme"
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(scheme)
    path.write_bytes(ET.tostring(scheme, encoding="utf-8", xml_declaration=True) + b"\n")
    print(f"Generated {len(source_builds)} app sources, {len(test_builds)} unit test sources, {len(ui_builds)} UI test sources")

if __name__ == "__main__":
    generate()
