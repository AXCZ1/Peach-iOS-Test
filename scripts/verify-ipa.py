"""Validate the packaged Peach test IPA on macOS with Xcode command line tools."""
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

APP = "PeachTest.app"
EXECUTABLE = "PeachTest"
BUNDLE_ID = "com.axcz1.peachios.test"
DISPLAY_NAME = "Peach Test"
VLC_FRAMEWORK = "VLCKit"
VLC_RELEASE = "VLCKit 4.0.0a25"


def require(condition, message):
    if not condition:
        raise SystemExit(f"IPA validation failed: {message}")


def tool(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    require(len(sys.argv) == 2, "usage: verify-ipa.py <ipa>")
    ipa = Path(sys.argv[1])
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, "ZIP integrity")
        names = archive.namelist()
        require(all(name.startswith("Payload/") for name in names), "Payload must be the ZIP root")
        require(all(".." not in Path(name).parts for name in names), "unsafe archive path")
        apps = {name.split("/")[1] for name in names if len(name.split("/")) > 1 and name.split("/")[1]}
        require(apps == {APP}, f"exactly one {APP} is required")
        root = f"Payload/{APP}/"
        plist = plistlib.loads(archive.read(root + "Info.plist"))
        require(plist.get("CFBundleExecutable") == EXECUTABLE, "CFBundleExecutable")
        require(plist.get("CFBundlePackageType") == "APPL", "application package type")
        require(plist.get("CFBundleIdentifier") == BUNDLE_ID, "bundle identifier")
        require(plist.get("CFBundleDisplayName") == DISPLAY_NAME, "display name")
        require(plist.get("MinimumOSVersion") == "17.0", "minimum iOS must be 17.0")
        require(plist.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "device SDK required")
        require(plist.get("UIDeviceFamily") == [1], "iPhone device family")
        require(plist.get("LSRequiresIPhoneOS") is True, "iOS required")
        require("UILaunchScreen" in plist, "launch screen")
        require(plist.get("CFBundleShortVersionString") == "1.0.0", "marketing version")
        require(str(plist.get("CFBundleVersion", "")).isdigit(), "numeric build version")
        require("audio" in plist.get("UIBackgroundModes", []), "background playback for Picture in Picture")
        require(root + "Assets.car" in names, "compiled app assets")
        notices = archive.read(root + "ThirdPartyNotices.txt").decode("utf-8")
        require(VLC_RELEASE in notices and "GNU LESSER GENERAL PUBLIC LICENSE" in notices,
                "VLC third-party notices")
        framework_root = root + f"Frameworks/{VLC_FRAMEWORK}.framework/"
        vlc_plist = plistlib.loads(archive.read(framework_root + "Info.plist"))
        require(vlc_plist.get("CFBundleExecutable") == VLC_FRAMEWORK, "VLC framework executable")
        vlc = archive.read(framework_root + VLC_FRAMEWORK)
        require(b"VLCSampleBufferDisplayView" in vlc, "VLC sample buffer renderer for Picture in Picture")
        require(not any("/_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names),
                "must be unsigned without a provisioning profile")
        info = archive.getinfo(root + EXECUTABLE)
        require(bool((info.external_attr >> 16) & stat.S_IXUSR), "executable permission")
        binary = archive.read(root + EXECUTABLE)
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / EXECUTABLE
        path.write_bytes(binary)
        os.chmod(path, 0o755)
        require(tool("xcrun", "lipo", "-archs", str(path)).split() == ["arm64"], "ARM64 device binary required")
        load_commands = tool("xcrun", "otool", "-l", str(path))
        require("LC_CODE_SIGNATURE" not in load_commands, "Mach-O code signature must be absent")
        build_info = tool("xcrun", "vtool", "-show-build", str(path))
        require(re.findall(r"\bplatform\s+([A-Z]+)\b", build_info) == ["IOS"], "Mach-O platform must be iOS")
        require(re.search(r"minos\s+17\.0\b", build_info) is not None, "Mach-O deployment version")
        require(f"@rpath/{VLC_FRAMEWORK}.framework/{VLC_FRAMEWORK}" in tool("xcrun", "otool", "-L", str(path)),
                "app must link the embedded decoder")
        require("@executable_path/Frameworks" in load_commands, "app framework run path")
        framework = Path(temporary) / VLC_FRAMEWORK
        framework.write_bytes(vlc)
        require(tool("xcrun", "lipo", "-archs", str(framework)).split() == ["arm64"], "VLC device ARM64 slice")
        vlc_commands = tool("xcrun", "otool", "-l", str(framework))
        require("LC_CODE_SIGNATURE" not in vlc_commands, "VLC must be unsigned")
        # The vendored binary uses the older device deployment load command.
        require("LC_VERSION_MIN_IPHONEOS" in vlc_commands or
                re.findall(r"\bplatform\s+([A-Z]+)\b", tool("xcrun", "vtool", "-show-build", str(framework))) == ["IOS"],
                "VLC must be built for iPhoneOS")
    print(json.dumps({
        "status": "passed",
        "ipa": ipa.name,
        "bytes": ipa.stat().st_size,
        "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
        "bundle_identifier": plist["CFBundleIdentifier"],
        "display_name": plist["CFBundleDisplayName"],
        "version": plist["CFBundleShortVersionString"],
        "build": plist["CFBundleVersion"],
        "minimum_ios": plist["MinimumOSVersion"],
        "architectures": "arm64",
        "local_decoder": VLC_RELEASE,
        "signed": False,
        "device_installation": "pending user validation",
    }, indent=2))


if __name__ == "__main__":
    main()
