"""CPU reference of Watch/Dial/WorldDial.fsh, for tuning the look offline. Keep the math identical to the shader.

Usage: python3 tools/textures/preview_shader.py <dir with the dial textures + world_env.png> <out.png> gx gy gz
gravity is in the watch's frame (x right, y toward 12 o'clock, z out of the screen), in g.
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

GOLD = np.array([1.00, 0.70, 0.36])        # rose gold reflectance (linear): absorbs blue strongly
SIGMA = np.array([3.4, 4.2, 0.55])         # ultramarine lacquer: absorbs green most, a little red passes (violet cast)
PIGMENT = np.array([0.030, 0.018, 0.21])   # light scattered back by the pigment
ENV_MAX = 256.0
AZ = 0.10                                  # turns the environment so the low sun sits off to one side
EXPOSURE = 1.3


def norm(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def dot(a, b):
    return np.sum(a * b, axis=-1, keepdims=True)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def sample(img, px):
    """Bilinear sample at pixel positions px (x, y), like texture2D with linear filtering and clamping."""
    return np.stack([ndimage.map_coordinates(img[..., i], [px[..., 1] - 0.5, px[..., 0] - 0.5], order=1, mode='nearest')
                     for i in range(img.shape[-1])], -1)


class Env:
    def __init__(self, img, up):
        self.img = img                                  # (384, 256, 3) log-encoded, three stacked levels
        U = up
        z = np.array([0.0, 0.0, 1.0])
        F = z - U * np.dot(U, z)
        if np.linalg.norm(F) < 0.15:                    # watch flat, face up: use 12 o'clock as "forward"
            F = F + 0.2 * (np.array([0.0, -1.0, 0.0]) - U * np.dot(U, np.array([0.0, -1.0, 0.0])))
        self.U, self.F = U, F / np.linalg.norm(F)
        self.Rt = np.cross(self.U, self.F)

    def __call__(self, r, level):
        x = dot(r, self.Rt)
        y = dot(r, self.U)
        z = dot(r, self.F)
        u = (np.arctan2(x, z) / (2 * np.pi) + 0.5 + AZ) % 1.0
        v = np.arccos(np.clip(y, -1, 1)) / np.pi
        v = np.clip(v, 0.5 / 128, 1 - 0.5 / 128)
        px = np.concatenate([u * 256, (level + v) * 128], -1)
        c = sample(self.img, px)
        return np.exp2(c * np.log2(1 + ENV_MAX)) - 1


def decode(enc):
    n = enc * 2 - 1
    return norm(np.concatenate([n, np.sqrt(np.clip(1 - np.sum(n * n, -1, keepdims=True), 0.05, 1))], -1))


def shade(t, g):
    metal_s, mat_s, metal_b, mat_b, env_img = t
    h, w = metal_s.shape[:2]
    tex = np.array([w, h], dtype=np.float64)
    view = tex
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    screen = np.stack([xx, yy], -1)

    # Domed sapphire crystal near the bezel
    cs = screen - tex * 0.5
    rad = 0.2 * view.min()
    qe = np.abs(cs) - view * 0.5 + rad
    d_edge = -(np.linalg.norm(np.maximum(qe, 0), axis=-1, keepdims=True) + np.minimum(np.max(qe, -1, keepdims=True), 0) - rad)
    sgn = np.where(cs < 0, -1.0, 1.0)
    n_edge = np.where(qe[..., 0:1] > qe[..., 1:2], np.concatenate([sgn[..., 0:1], 0 * sgn[..., 1:2]], -1),
                      np.concatenate([0 * sgn[..., 0:1], sgn[..., 1:2]], -1))
    corner = (qe[..., 0:1] > 0) & (qe[..., 1:2] > 0)
    n_edge = np.where(corner, norm(np.maximum(qe, 1e-6)) * sgn, n_edge)
    band = 0.10 * view.min()
    t_edge = np.clip(1 - d_edge / band, 0, 1)
    px = screen - n_edge * band * 0.30 * t_edge ** 3

    # Depth of field: sharp at the centre of the globe, soft toward the rim and the bezel
    c = px - tex * 0.5
    R = 0.43 * w
    lc = np.linalg.norm(c, axis=-1, keepdims=True)
    dof = np.clip(smooth(0.75, 1.25, lc / R) * 0.55 + t_edge, 0, 1)
    m = sample(metal_s, px) * (1 - dof) + sample(metal_b, px) * dof
    q = sample(mat_s, px) * (1 - dof) + sample(mat_b, px) * dof

    p = np.concatenate([px, np.zeros((h, w, 1))], -1)
    eye = np.array([w / 2, h / 2, 2.4 * w])
    v = norm(eye - p)
    up = np.array([-g[0], g[1], -g[2]])
    upn = up / np.linalg.norm(up)
    env = Env(env_img, upn)

    n_metal = decode(m[..., 0:2])
    hgt = m[..., 2:3]
    gold_m, flake, ao = q[..., 0:1], q[..., 1:2], q[..., 2:3]

    Rs = R * 1.9
    rr = np.minimum(lc, R)
    dome = norm(np.concatenate([c * (rr / np.maximum(lc, 0.001)), np.sqrt(Rs * Rs - rr * rr)], -1))
    n_coat = np.where(lc < R, dome, np.array([0.0, 0.0, 1.0]))

    # Rose gold: satin metal mirroring the real environment, tinted by its colour
    nov = np.clip(dot(n_metal, v), 0.001, 1)
    r = 2 * nov * n_metal - v
    fres = GOLD + (1 - GOLD) * (1 - nov) ** 5
    cavity = np.clip(0.75 + 0.5 * hgt, 0, 1)
    refl = env(r, 1) * 0.78 + env(r, 0) * 0.22
    gold = fres * refl * (cavity + (1 - cavity) * GOLD) * 1.1

    # Blue lacquer: glassy surface over a bright metal base, coloured by absorption
    ncv = np.clip(dot(n_coat, v), 0.001, 1)
    rc = 2 * ncv * n_coat - v
    fc = 0.04 + 0.96 * (1 - ncv) ** 5
    coat = fc * (env(rc, 0) * (1 - 0.7 * dof) + env(rc, 1) * 0.7 * dof)
    rb = 2 * dot(n_metal, v) * n_metal - v
    path = hgt * 2.8 * (0.5 + 0.5 / np.maximum(ncv, 0.25))
    trans = np.exp(-SIGMA * path)
    base = 0.75 * env(rb, 2)
    amb = env(n_coat, 2)
    pigment = PIGMENT * (0.4 + 0.6 * np.clip(dot(amb, np.ones(3) / 3), 0, 3))
    body = (base * trans + pigment) * (1 - fc) * ao


    col = gold * gold_m + (body + coat) * (1 - gold_m)

    col = col * (1 - 0.45 * t_edge ** 3)
    nb = norm(np.concatenate([n_edge * (t_edge * 1.1), np.ones_like(t_edge)], -1))
    rb2 = 2 * dot(nb, v) * nb - v
    col = col + t_edge ** 2 * 0.08 * env(rb2, 0)
    col = 1 - np.exp(-col * EXPOSURE)
    return np.clip(col, 0, 1) ** (1 / 1.15)


def load(d):
    f = lambda n: np.asarray(Image.open(f'{d}/{n}.png').convert('RGB'), dtype=np.float64) / 255
    return f('world_metal'), f('world_mat'), f('world_metal_dof'), f('world_mat_dof'), f('world_env')


if __name__ == '__main__':
    g = np.array([float(x) for x in sys.argv[3:6]])
    g = g / np.linalg.norm(g)
    Image.fromarray((shade(load(sys.argv[1]), g) * 255).astype(np.uint8)).save(sys.argv[2])
