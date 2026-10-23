"""Fast regression checks, complementary to the compiler's deployment-target checks."""
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = [r"\bNavigationStack\b", r"\bNavigationSplitView\b", r"\bPhotosPicker\b", r"\bSwiftData\b", r"\.bytes\(for:", r"AttributedString\(markdown:", r"\.safeAreaInset\(", r"\.task\s*\{", r"\.searchable\(", r"\.textSelection\(", r"\.presentationDetents\("]

def main():
    project = (ROOT / "AkiChat.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    targets = re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = "([^"]+)"', project)
    assert len(targets) == 8 and set(targets) == {"14.0"}, targets
    assert 'PRODUCT_BUNDLE_IDENTIFIER = "com.akisenn.akichat"' in project
    scheme = ET.parse(ROOT / "AkiChat.xcodeproj/xcshareddata/xcschemes/AkiChat.xcscheme")
    assert scheme.find(".//TestableReference/BuildableReference") is not None
    with (ROOT / "AkiChat/Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert info["LSRequiresIPhoneOS"] and info["CFBundleExecutable"] == "$(EXECUTABLE_NAME)"
    assert info.get("NSAppTransportSecurity") == {"NSAllowsLocalNetworking": True}
    assert info.get("NSLocalNetworkUsageDescription")
    for path in (ROOT / "AkiChat").rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for pattern in FORBIDDEN:
            assert not re.search(pattern, text), f"Newer API needs manual review: {path}: {pattern}"
        assert not re.search(r"UserDefaults.*(?:key|Key)", text), path
        assert not re.search(r"(?:print|NSLog|debugPrint)\s*\(", text), f"Unexpected runtime logging: {path}"
        assert "serverTrust" not in text, f"TLS override: {path}"
    assert not list(ROOT.rglob("Package.resolved")), "Review deployment targets and licenses before adding packages"
    print("iOS 14 source/project checks passed (compiler availability checking still required)")

if __name__ == "__main__":
    main()
