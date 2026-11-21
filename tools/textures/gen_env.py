"""Bake the reflection environment for the World dial from a photographic HDR (equirectangular).

Writes world_env.png (256 x 384, RGB): three 256 x 128 equirectangular maps stacked top to bottom,
  0  sharp  - what the polished lacquer and crystal mirror
  1  satin  - what the satin rose gold reflects (blurred ~10 degrees)
  2  soft   - what the metal under the lacquer reflects (blurred ~25 degrees)
Values are log-encoded: c = log2(1 + L) / log2(1 + MAX); the shader decodes L = 2^(c * log2(1 + MAX)) - 1.
Texel (0,0) is mid-grey (calibration, as in the other dial textures).

Usage: python3 tools/textures/gen_env.py <env.hdr> <out_dir>
Source used: venice_sunset_1k.hdr (Poly Haven, CC0; via the three.js examples).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rgbe import read_hdr  # noqa: E402

MAX = 256.0
W, H = 256, 128


def blur_equirect(img, sigma_deg):
    """Gaussian blur on the sphere, approximated per row (wider in x near the poles)."""
    h, w = img.shape[:2]
    out = np.empty_like(img)
    sy = sigma_deg / 180 * h
    tmp = np.stack([ndimage.gaussian_filter1d(img[..., c], sy, axis=0, mode='nearest') for c in range(3)], -1)
    for y in range(h):
        lat = (0.5 - (y + 0.5) / h) * np.pi
        sx = sigma_deg / 360 * w / max(np.cos(lat), 0.08)
        for c in range(3):
            out[y, :, c] = ndimage.gaussian_filter1d(tmp[y, :, c], min(sx, w / 3), mode='wrap')
    return out


def main(hdr, out_dir):
    env = read_hdr(hdr).astype(np.float64)
    small = np.stack([np.asarray(Image.fromarray(env[..., c].astype(np.float32), 'F').resize((W, H), Image.BOX)) for c in range(3)], -1)
    sharp = blur_equirect(small, 1.2)
    satin = blur_equirect(small, 10.0)
    soft = blur_equirect(small, 25.0)
    stack = np.concatenate([sharp, satin, soft], 0)
    enc = np.log2(1 + np.clip(stack, 0, MAX)) / np.log2(1 + MAX)
    enc[0, 0, :] = 128 / 255
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(enc, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(out / 'world_env.png', optimize=True)
    print('ok', stack.shape, 'max', float(stack.max()))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
