#!/usr/bin/env python3
"""Build Resources/AppIcon.icns from the direction-A SVG masters (box/dev tool).

  python3 scripts/make-icns.py            # render with rsvg-convert, pack, verify
  python3 scripts/make-icns.py --verify Resources/AppIcon.icns

Pixel sizes <= 32 use the simplified master (A-lifted-slice-small.svg, legible
at 16/32 px); larger sizes use A-lifted-slice.svg. The icns container
('icns' + big-endian length, then OSType/length/PNG chunks) is written by hand;
no png2icns/iconutil needed. Writes only Resources/AppIcon.icns and a temp dir.
"""
import os, struct, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# (iconset name, OSType, pixel size)
SLOTS = [
    ("icon_16x16",      b"icp4", 16),   ("icon_16x16@2x",   b"ic11", 32),
    ("icon_32x32",      b"icp5", 32),   ("icon_32x32@2x",   b"ic12", 64),
    ("icon_128x128",    b"ic07", 128),  ("icon_128x128@2x", b"ic13", 256),
    ("icon_256x256",    b"ic08", 256),  ("icon_256x256@2x", b"ic14", 512),
    ("icon_512x512",    b"ic09", 512),  ("icon_512x512@2x", b"ic10", 1024),
]
EXPECTED = {t: px for _, t, px in SLOTS}

def render(svg, px, out):
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg, "-o", out], check=True)

def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])

def verify(path):
    data = open(path, "rb").read()
    if data[:4] != b"icns": raise SystemExit("FAIL: bad magic")
    (total,) = struct.unpack(">I", data[4:8])
    if total != len(data): raise SystemExit(f"FAIL: header length {total} != file size {len(data)}")
    seen, off = {}, 8
    while off < len(data):
        t, n = data[off:off+4], struct.unpack(">I", data[off+4:off+8])[0]
        if n < 8 or off + n > len(data): raise SystemExit(f"FAIL: chunk {t!r} overruns file")
        w, h = png_size(data[off+8:off+n])
        seen[t] = (w, h); off += n
    for t, px in EXPECTED.items():
        if seen.get(t) != (px, px): raise SystemExit(f"FAIL: {t.decode()} missing or wrong size ({seen.get(t)})")
    for t, (w, _) in sorted(seen.items(), key=lambda kv: kv[1][0]):
        print(f"  {t.decode()}  {w}x{w}")
    print(f"OK: {path} — {len(seen)} PNG chunks, {len(data)} bytes")

def build():
    big = os.path.join(ROOT, "Resources/icon-master/A-lifted-slice.svg")
    small = os.path.join(ROOT, "Resources/icon-master/A-lifted-slice-small.svg")
    out = os.path.join(ROOT, "Resources/AppIcon.icns")
    chunks = b""
    with tempfile.TemporaryDirectory() as tmp:
        cache = {}
        for name, ostype, px in SLOTS:
            if px not in cache:
                p = os.path.join(tmp, f"{px}.png")
                render(small if px <= 32 else big, px, p)
                cache[px] = open(p, "rb").read()
            data = cache[px]
            assert png_size(data) == (px, px), name
            chunks += ostype + struct.pack(">I", len(data) + 8) + data
    open(out, "wb").write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
    verify(out)

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--verify": verify(sys.argv[2])
    else: build()
