"""PT1d: checks a macOS export zip made on Linux: the app bundle's executable is present and executable (0755), it is a
universal binary (x86_64 + arm64), and every slice carries an ad-hoc code signature (Apple Silicon refuses unsigned
native code). Usage: python3 check_macos_export.py "dist/macos/OpenRC Simulator.zip"
"""
import struct
import sys
import zipfile

CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}
LC_CODE_SIGNATURE = 0x1D
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CS_ADHOC = 0x2

problems = []
z = zipfile.ZipFile(sys.argv[1])
exes = [i for i in z.infolist() if "/Contents/MacOS/" in i.filename and not i.filename.endswith("/")]
if len(exes) != 1:
    sys.exit(f"FAIL expected one executable in Contents/MacOS, found {[i.filename for i in exes]}")
info = exes[0]
mode = (info.external_attr >> 16) & 0o777
if mode & 0o111 == 0:
    problems.append(f"{info.filename} is not executable (mode {oct(mode)})")
data = z.read(info)


def slice_signature(buf):
    magic, cputype = struct.unpack_from("<II", buf, 0)
    if magic != 0xFEEDFACF:
        return None, "not a 64-bit Mach-O slice"
    ncmds = struct.unpack_from("<I", buf, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", buf, off)
        if cmd == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from("<II", buf, off + 8)
            sb = buf[dataoff:dataoff + datasize]
            count = struct.unpack_from(">I", sb, 8)[0]
            for k in range(count):
                _, boff = struct.unpack_from(">II", sb, 12 + 8 * k)
                if struct.unpack_from(">I", sb, boff)[0] == CSMAGIC_CODEDIRECTORY:
                    flags = struct.unpack_from(">I", sb, boff + 12)[0]
                    return CPU.get(cputype, hex(cputype)), "ad-hoc signed" if flags & CS_ADHOC else f"signed, flags {flags:#x}"
            return CPU.get(cputype, hex(cputype)), "signature without a code directory"
        off += size
    return CPU.get(cputype, hex(cputype)), "UNSIGNED"


slices = []
if struct.unpack_from(">I", data, 0)[0] == 0xCAFEBABE:  # universal (fat) binary
    for k in range(struct.unpack_from(">I", data, 4)[0]):
        _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + 20 * k)
        slices.append(slice_signature(data[offset:offset + size]))
else:
    slices.append(slice_signature(data))
archs = sorted(a for a, _ in slices)
if archs != ["arm64", "x86_64"]:
    problems.append(f"not universal: {archs}")
for arch, sig in slices:
    if sig != "ad-hoc signed":
        problems.append(f"{arch}: {sig}")
print(f"macOS export: {info.filename} mode {oct(mode)}, slices {', '.join(f'{a} {s}' for a, s in slices)}")
if problems:
    print("FAIL " + "; ".join(problems))
    sys.exit(1)
