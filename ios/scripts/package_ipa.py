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

def validate_app(app):
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert app.name == "AkiChat.app"
    assert info["CFBundleIdentifier"] == "app.akichat.ios"
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
    assert not info.get("NSAppTransportSecurity")
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
            output("codesign", "--force", "--sign", "-", "--identifier", "app.akichat.ios", str(copied))
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
