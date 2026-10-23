"""Only packages a real, validated arm64 iPhoneOS app built by xcodebuild."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

def embedded_binaries(app):
    binaries = []
    for path in app.rglob("*"):
        if not path.is_file() or path.name == "AkiChat":
            continue
        with path.open("rb") as f:
            magic = f.read(4)
        if magic in [b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"]:
            binaries.append(path)
    return binaries

def validate_embedded(app):
    for binary in embedded_binaries(app):
        assert "arm64" in output("lipo", "-archs", str(binary)).split(), f"Missing arm64: {binary}"
        loads = output("otool", "-arch", "arm64", "-l", str(binary))
        versions = re.findall(r"^\s*(?:minos|version)\s+(\d+\.\d+(?:\.\d+)?)\s*$", loads, re.M)
        assert versions, f"Missing deployment metadata: {binary}"
        assert all(tuple(map(int, v.split('.')))[:2] <= (14, 0) for v in versions), f"Embedded binary requires a newer OS: {binary}"
        assert re.search(r"^\s*platform\s+2\s*$", loads, re.M) or "LC_VERSION_MIN_IPHONEOS" in loads, f"Non-iPhoneOS framework: {binary}"

def validate_app(app):
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert app.name == "AkiChat.app"
    assert info["CFBundleIdentifier"] == "com.akisenn.akichat"
    assert info["MinimumOSVersion"] == "14.0", info.get("MinimumOSVersion")
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    assert info["CFBundleExecutable"] == "AkiChat"
    binary = app / info["CFBundleExecutable"]
    assert binary.is_file() and binary.stat().st_size > 100_000
    assert binary.stat().st_mode & stat.S_IXUSR
    assert output("lipo", "-archs", str(binary)).strip() == "arm64"
    loads = output("otool", "-l", str(binary))
    assert re.search(r"(?:minos|version)\s+14\.0(?:\s|$)", loads), "Mach-O minimum OS mismatch"
    assert (app / "Assets.car").is_file()
    assert not (app / "embedded.mobileprovision").exists()
    assert info.get("NSAppTransportSecurity") == {"NSAllowsLocalNetworking": True}, "Only local networking ATS exception is allowed"
    assert info.get("NSLocalNetworkUsageDescription")
    validate_embedded(app)
    return binary

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--adhoc", action="store_true")
    args = parser.parse_args()
    validate_app(args.app)
    args.ipa.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        copied = root / "Payload/AkiChat.app"
        shutil.copytree(args.app, copied, symlinks=True)
        binary = copied / "AkiChat"
        if args.adhoc:
            # Local ad-hoc only: no Apple account, certificate, provisioning, or private entitlements.
            for embedded in embedded_binaries(copied):
                target = embedded.parent if embedded.parent.suffix == ".framework" else embedded
                output("codesign", "--force", "--sign", "-", str(target))
            output("codesign", "--force", "--sign", "-", "--identifier", "com.akisenn.akichat", str(copied))
            output("codesign", "--verify", "--strict", str(copied))
        else:
            result = subprocess.run(["codesign", "-dv", str(copied)], capture_output=True, text=True)
            assert result.returncode != 0 and "not signed at all" in result.stderr, "Unsigned artifact must truly be unsigned"
        validate_app(copied)
        with zipfile.ZipFile(args.ipa, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(root.rglob("*")):
                if path.is_file(): archive.write(path, path.relative_to(root).as_posix())
    with zipfile.ZipFile(args.ipa) as archive:
        assert archive.testzip() is None
        assert all(name.startswith("Payload/AkiChat.app/") for name in archive.namelist())
        assert archive.read("Payload/AkiChat.app/AkiChat")[:4] in [b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"]
        info = plistlib.loads(archive.read("Payload/AkiChat.app/Info.plist"))
        assert info["MinimumOSVersion"] == "14.0"
    print(f"Validated actual device IPA: {args.ipa} ({args.ipa.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
