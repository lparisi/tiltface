"""Minimal Radiance .hdr (RGBE, run-length encoded) reader -> float32 (h, w, 3) linear radiance."""
import numpy as np


def read_hdr(path):
    data = open(path, 'rb').read()
    pos = 0
    while True:                                   # header lines until an empty line
        end = data.index(b'\n', pos)
        line = data[pos:end]
        pos = end + 1
        if line == b'':
            break
    end = data.index(b'\n', pos)
    dims = data[pos:end].split()
    pos = end + 1
    h, w = int(dims[1]), int(dims[3])             # "-Y h +X w"
    img = np.zeros((h, w, 4), dtype=np.uint8)
    buf = np.frombuffer(data, dtype=np.uint8)
    for y in range(h):
        if buf[pos] == 2 and buf[pos + 1] == 2:   # new-style RLE scanline
            pos += 4
            for c in range(4):
                x = 0
                while x < w:
                    n = int(buf[pos])
                    pos += 1
                    if n > 128:
                        n -= 128
                        img[y, x:x + n, c] = buf[pos]
                        pos += 1
                    else:
                        img[y, x:x + n, c] = buf[pos:pos + n]
                        pos += n
                    x += n
        else:                                     # flat scanline
            img[y] = buf[pos:pos + w * 4].reshape(w, 4)
            pos += w * 4
    e = img[..., 3].astype(np.int32)
    scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
    return (img[..., :3].astype(np.float32) * scale[..., None]).astype(np.float32)
