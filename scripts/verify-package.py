"""Check device architecture, embedded keyboard and App Group requirements."""
import json
import plistlib
import struct
import sys
from pathlib import Path

EXPECTED_GROUP = "group.com.jevchat.jarvis"


def inspect_bundle(bundle, expected_id):
    with (bundle / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleIdentifier"] != expected_id:
        raise ValueError(f"Unexpected bundle identifier: {bundle}")
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError(f"Not an iPhone device build: {bundle}")
    binary = bundle / info["CFBundleExecutable"]
    with binary.open("rb") as stream:
        header = stream.read(32)
    if len(header) != 32:
        raise ValueError(f"Truncated executable: {binary}")
    magic, cpu = struct.unpack_from("<II", header)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError(f"Executable is not a thin arm64 Mach-O: {binary}")
    return {"bundle_id": expected_id, "architecture": "arm64", "platform": "iphoneos"}


def main():
    app = Path(sys.argv[1])
    keyboard = app / "PlugIns" / "JevKeyboard.appex"
    result = {
        "app": inspect_bundle(app, "com.jevchat.jarvis"),
        "keyboard": inspect_bundle(keyboard, "com.jevchat.jarvis.keyboard"),
    }
    with (keyboard / "Info.plist").open("rb") as stream:
        extension = plistlib.load(stream)["NSExtension"]
    if extension["NSExtensionPointIdentifier"] != "com.apple.keyboard-service":
        raise ValueError("Embedded extension is not a custom keyboard")
    if extension["NSExtensionAttributes"].get("RequestsOpenAccess") is not True:
        raise ValueError("Keyboard is missing its network access request")
    logs = Path(__file__).resolve().parents[1] / "logs"
    for name in ("app", "keyboard"):
        with (logs / f"{name}-entitlements.plist").open("rb") as stream:
            entitlements = plistlib.load(stream)
        if entitlements.get("com.apple.security.application-groups") != [EXPECTED_GROUP]:
            raise ValueError(f"Missing or changed App Group in {name}")
    result["app_group"] = EXPECTED_GROUP
    result["apple_installation_signature"] = False
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
