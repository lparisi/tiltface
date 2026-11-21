"""CPU reference of Watch/Dial/WorldDial.fsh, for tuning the look offline. Keep the math identical to the shader.

Usage: python3 tools/textures/preview_shader.py <dir with world_metal.png + world_mat.png> <out.png> gx gy gz
gravity is in the watch's frame (x right, y toward 12 o'clock, z out of the screen), in g.
"""
import sys

import numpy as np
from PIL import Image

GOLD = np.array([1.00, 0.80, 0.55])        # pale champagne rose gold (5N, satin), display-referred
SIGMA = np.array([3.4, 4.2, 0.55])         # ultramarine lacquer: absorbs green most, a little red passes (violet cast)
PIGMENT = np.array([0.030, 0.018, 0.21])   # light scattered back by the pigment (violet-blue)


def norm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def dot(a, b):
    return np.sum(a * b, axis=-1, keepdims=True)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def env_metal(r, up, key, fill, rough, viewer_dark=0.55):
    """The room as a metal mirrors it: bright ceiling, dark floor, a hot softbox and a window, and a dark zone
    behind the viewer (straight-on reflections show the person wearing the watch, not a light).
    High contrast is what makes metal read as metal; rough = blurrier lights."""
    hgt = dot(r, up)
    t = smooth(-0.3, 0.9, hgt)
    viewer = 1 - viewer_dark * smooth(0.86, 0.99, r[..., 2:3])
    room = (0.03 + 1.0 * t * t) * viewer
    k = np.clip(dot(r, key), 0, 1)
    f = np.clip(dot(r, fill), 0, 1)
    e = 8 + (1 - rough) * 70
    return room + 1.6 * k ** e + 4.0 * k ** (e * 5) + 1.1 * f ** (e * 0.7)


def env_coat(r, up, key, fill):
    """What the polished lacquer mirrors: a soft, elongated window (not a disk) and a broad bright ceiling sheen."""
    side = norm(np.cross(np.broadcast_to(up, r.shape), np.broadcast_to(key, r.shape)) + 1e-9)
    along = dot(r, side)                       # across the window
    k = dot(r, key)
    window = smooth(0.90, 0.97, k + 0.9 * along * along) * smooth(-0.35, -0.2, -np.abs(along)) * 2.2
    sheen = 0.25 * smooth(0.2, 0.95, dot(r, up))
    room = 0.04
    return window + sheen + room


def decode(enc):
    n = enc * 2 - 1
    return norm(np.concatenate([n, np.sqrt(np.clip(1 - np.sum(n * n, -1, keepdims=True), 0.05, 1))], -1))


def sample(img, px):
    """Bilinear sample of an (h, w, c) image at pixel positions px (x, y), like texture2D with linear filtering."""
    from scipy import ndimage
    return np.stack([ndimage.map_coordinates(img[..., i], [px[..., 1] - 0.5, px[..., 0] - 0.5], order=1, mode='nearest')
                     for i in range(img.shape[-1])], -1)


def lens(px, view, tex):
    """Domed sapphire crystal: near the bezel the dial is seen magnified and pulled inward.
    Returns (distorted sample position, edge factor t in 0..1, outward edge normal)."""
    c = px - tex * 0.5
    half = view * 0.5
    rad = 0.2 * view.min()
    q = np.abs(c) - half + rad
    outside = np.linalg.norm(np.maximum(q, 0), axis=-1, keepdims=True)
    d = -(outside + np.minimum(np.max(q, -1, keepdims=True), 0) - rad)       # distance inside the edge
    sgn = np.sign(c) + (c == 0)
    corner = (q[..., 0:1] > 0) & (q[..., 1:2] > 0)
    n_corner = np.maximum(q, 1e-6) / np.maximum(np.linalg.norm(np.maximum(q, 1e-6), axis=-1, keepdims=True), 1e-6) * sgn
    n_side = np.where(q[..., 0:1] > q[..., 1:2], np.concatenate([sgn[..., 0:1], 0 * sgn[..., 1:2]], -1),
                      np.concatenate([0 * sgn[..., 0:1], sgn[..., 1:2]], -1))
    n_edge = np.where(corner, n_corner, n_side)
    band = 0.10 * view.min()
    t = np.clip(1 - d / band, 0, 1)
    pull = band * 0.30 * t * t * t
    return px - n_edge * pull, t, n_edge


def shade(metal, mat, g, view=None):
    h, w = metal.shape[:2]
    tex = np.array([w, h], dtype=np.float64)
    view = tex if view is None else view
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    screen = np.stack([xx, yy], -1)
    px, t_edge, n_edge = lens(screen, view, tex)
    metal = sample(metal, px)
    mat = sample(mat, px)
    p = np.concatenate([px, np.zeros((h, w, 1))], -1)
    eye = np.array([w / 2, h / 2, 2.4 * w])
    v = norm(eye - p)
    up = np.array([-g[0], g[1], -g[2]])
    upn = norm(up)
    key = norm(up + np.array([-0.30, -0.42, 0.0]))
    fill = norm(up + np.array([0.95, 0.10, -0.15]))

    n_metal = decode(metal[..., 0:2])
    hgt = metal[..., 2:3]
    gold_m, flake, ao = mat[..., 0:1], mat[..., 1:2], mat[..., 2:3]

    c = px - tex * 0.5
    R = 0.43 * w
    Rs = R * 1.9
    lc = np.linalg.norm(c, axis=-1, keepdims=True)
    rr = np.minimum(lc, R)
    dome = norm(np.concatenate([c * (rr / np.maximum(lc, 0.001)), np.sqrt(Rs * Rs - rr * rr)], -1))
    n_coat = np.where(lc < R, dome, np.array([0.0, 0.0, 1.0]))

    nov = np.clip(dot(n_metal, v), 0.001, 1)
    r = 2 * nov * n_metal - v
    fres = GOLD + (1 - GOLD) * (1 - nov) ** 5
    # Light bouncing between ridges of the relief picks up the gold colour twice (deeper, more saturated).
    cavity = np.clip(0.75 + 0.5 * hgt, 0, 1)
    gold = 1.18 * fres * env_metal(r, upn, key, fill, 0.2, 0.2) * (cavity + (1 - cavity) * GOLD)

    ncv = np.clip(dot(n_coat, v), 0.001, 1)
    rc = 2 * ncv * n_coat - v
    fc = 0.04 + 0.96 * (1 - ncv) ** 5
    coat = fc * env_coat(rc, upn, key, fill)
    rb = 2 * dot(n_metal, v) * n_metal - v
    path = hgt * 2.8 * (0.5 + 0.5 / np.maximum(ncv, 0.25))
    trans = np.exp(-SIGMA * path)
    base = 0.7 * env_metal(rb, upn, key, fill, 0.1, 0.0)
    pigment = PIGMENT * (0.35 + 0.65 * np.clip(dot(n_coat, key), 0, 1))
    body = (base * trans + pigment) * (1 - fc) * ao

    ang = flake * 6.2831 * 7.0
    nf = norm(np.concatenate([np.cos(ang) * 0.45, np.sin(ang) * 0.45, np.ones_like(ang)], -1))
    rf = 2 * dot(nf, v) * nf - v
    glint = GOLD * np.clip(dot(rf, key), 0, 1) ** 90 * 9.0 + GOLD * 0.10
    body = np.where(flake > 0.02, body * 0.4 + glint, body)

    col = gold * gold_m + (body + coat) * (1 - gold_m)

    # Crystal edge: darker toward the bezel, plus the bevel of the sapphire catching the light.
    col = col * (1 - 0.45 * t_edge ** 3)
    nb = norm(np.concatenate([n_edge * (t_edge * 1.1), np.ones_like(t_edge)], -1))
    rb2 = 2 * dot(nb, v) * nb - v
    col = col + t_edge ** 2 * 0.25 * env_coat(rb2, upn, key, fill)
    col = 1 - np.exp(-col * 1.2)
    return np.clip(col, 0, 1) ** (1 / 1.15)


if __name__ == '__main__':
    d = sys.argv[1]
    metal = np.asarray(Image.open(f'{d}/world_metal.png').convert('RGB'), dtype=np.float64) / 255
    mat = np.asarray(Image.open(f'{d}/world_mat.png').convert('RGB'), dtype=np.float64) / 255
    g = np.array([float(x) for x in sys.argv[3:6]])
    g = g / np.linalg.norm(g)
    Image.fromarray((shade(metal, mat, g) * 255).astype(np.uint8)).save(sys.argv[2])
