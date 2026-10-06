"""Version fields of the exported builds (MENU-PLAN UI-04a, research 21). Standard library only.

Usage: check_build_versions.py <OpenRC Simulator.exe> <OpenRC Simulator.zip (macOS)> <x.y.z>
- Windows: the VERSIONINFO strings FileVersion and ProductVersion are x.y.z.0 (Godot writes 1.0.0.0 when it
  finds no numeric version: that is the bug this guards against).
- macOS: Info.plist CFBundleShortVersionString and CFBundleVersion are x.y.z.
"""
import plistlib
import sys
import zipfile

exe, mac_zip, numeric = sys.argv[1], sys.argv[2], sys.argv[3]
problems = []


def version_string(blob: bytes, key: str) -> str:
    """The UTF-16LE value that follows a StringFileInfo key in a PE file's VERSIONINFO resource."""
    i = blob.find(key.encode("utf-16-le") + b"\x00\x00")
    if i < 0:
        return ""
    j = i + len(key) * 2 + 2
    while j < len(blob) and blob[j:j + 2] == b"\x00\x00":  # padding to a 32-bit boundary
        j += 2
    end = blob.find(b"\x00\x00", j)
    while end >= 0 and (end - j) % 2:
        end = blob.find(b"\x00\x00", end + 1)
    return blob[j:end].decode("utf-16-le", "replace") if end >= 0 else ""


blob = open(exe, "rb").read()
for key in ("FileVersion", "ProductVersion"):
    found = version_string(blob, key)
    if found != numeric + ".0":
        problems.append(f".exe {key} is '{found}', expected '{numeric}.0'")

with zipfile.ZipFile(mac_zip) as z:
    names = [n for n in z.namelist() if n.endswith(".app/Contents/Info.plist")]
    if not names:
        problems.append("no Contents/Info.plist in the macOS zip")
    else:
        plist = plistlib.loads(z.read(names[0]))
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if plist.get(key) != numeric:
                problems.append(f"Info.plist {key} is '{plist.get(key)}', expected '{numeric}'")

if problems:
    print("FAIL " + "; ".join(problems))
    sys.exit(1)
print(f"version fields: .exe {numeric}.0 (FileVersion, ProductVersion), Info.plist {numeric} (short and bundle version)")
