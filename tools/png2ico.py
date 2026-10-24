#!/usr/bin/env python3
"""Pack PNG files (PNG-compressed entries) into a Windows .ico.   png2ico.py out.ico a.png b.png ..."""
import struct
import sys

out, pngs = sys.argv[1], sys.argv[2:]
images = []
for path in pngs:
    data = open(path, "rb").read()
    w, h = struct.unpack(">II", data[16:24])
    images.append((w, h, data))
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, blobs = b"", b""
for w, h, data in images:
    entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(data), offset)
    blobs += data
    offset += len(data)
open(out, "wb").write(header + entries + blobs)
print(f"{out}: {len(images)} images")
