"""Generate the World face dial textures (run offline; outputs go into Watch/Assets.xcassets).

Inputs: Natural Earth 1:50m land polygons (public domain), procedural noise.
Outputs (432 x 528 px, ~1 px per screen pixel on a 45/46 mm Apple Watch at 2x), opaque RGB so nothing is premultiplied:

  world_metal.png  R,G  normal x,y of the metal surface (gold relief, or the stamped base under the lacquer), 0.5 = flat
                   B    gold: relief height / lacquer: thickness (x 2.8)
  world_mat.png    R    material: 1 = rose gold, 0 = blue lacquer
                   G    facet seed of gold flakes in the lacquer (0 = none)
                   B    ambient occlusion

The lacquer's top surface (a smooth dome over the globe) is computed in the shader.
Texel (0,0) of both files is mid-grey (128): the shader reads it to detect whether the texture was linearised on upload.
Normals are in screen space: x right, y down, z toward the viewer.

Also writes world_metal_dof.png / world_mat_dof.png (blurred copies for the depth of field).

Usage: python3 tools/textures/gen_world_dial.py <ne_50m_land.geojson> <out_dir>
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from scipy.spatial import cKDTree

W, H = 432, 528            # final texture size
SS = 2                     # supersampling for generation
GW, GH = W * SS, H * SS
R = 0.43 * W * SS          # globe radius (generation px)
CX, CY = GW / 2, GH / 2
LAT0, LON0 = np.radians(8.0), np.radians(-32.0)   # globe centre: mid-Atlantic, slightly north
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- noise
def value_noise(shape, cells, seed):
    g = np.random.default_rng(seed).random((cells[0] + 3, cells[1] + 3))
    z = ndimage.zoom(g, ((shape[0] + 1) / (cells[0] + 3) * 1.0, (shape[1] + 1) / (cells[1] + 3) * 1.0), order=3)
    return z[: shape[0], : shape[1]] * 2 - 1


def fbm(shape, base, octaves, seed, gain=0.5):
    out = np.zeros(shape)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = (max(2, int(base * shape[0] / shape[1] * 2 ** o)), max(2, int(base * 2 ** o)))
        out += amp * value_noise(shape, c, seed + o * 101)
        tot += amp
        amp *= gain
    return out / tot


def ridged(shape, base, octaves, seed):
    out = np.zeros(shape)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = (max(2, int(base * shape[0] / shape[1] * 2 ** o)), max(2, int(base * 2 ** o)))
        n = 1 - np.abs(value_noise(shape, c, seed + o * 37))
        out += amp * n * n
        tot += amp
        amp *= 0.55
    return out / tot


def crumple(shape, n_points, seed):
    """Voronoi F2-F1: a network of sharp creases, like hammered / stamped leaf."""
    r = np.random.default_rng(seed)
    pts = r.random((n_points, 2)) * np.array(shape)
    yy, xx = np.mgrid[0: shape[0], 0: shape[1]]
    d, _ = cKDTree(pts).query(np.stack([yy.ravel(), xx.ravel()], 1), k=2)
    f = (d[:, 1] - d[:, 0]).reshape(shape)
    return np.clip(f / np.percentile(f, 95), 0, 1)


# ---------------------------------------------------------------- land
def land_raster(geojson, width=8192):
    height = width // 2
    img = Image.new('L', (width, height), 0)
    draw = ImageDraw.Draw(img)

    def ring(coords):
        return [((lon + 180) / 360 * width, (90 - lat) / 180 * height) for lon, lat in coords]

    for f in json.load(open(geojson))['features']:
        geom = f['geometry']
        polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
        for poly in polys:
            draw.polygon(ring(poly[0]), fill=255)
            for hole in poly[1:]:
                draw.polygon(ring(hole), fill=0)
    return np.asarray(img, dtype=np.float32) / 255


def project():
    """Orthographic globe: for every generation pixel, where it lands on an equirectangular map (u, v in 0..1)."""
    yy, xx = np.mgrid[0:GH, 0:GW].astype(np.float64)
    x = (xx + 0.5 - CX) / R
    y = -(yy + 0.5 - CY) / R          # y up for the projection
    rho = np.sqrt(x * x + y * y)
    inside = rho < 1
    c = np.arcsin(np.clip(rho, 0, 1))
    with np.errstate(invalid='ignore', divide='ignore'):
        lat = np.arcsin(np.cos(c) * np.sin(LAT0) + np.where(rho > 0, y * np.sin(c) * np.cos(LAT0) / rho, 0))
        lon = LON0 + np.arctan2(x * np.sin(c), rho * np.cos(c) * np.cos(LAT0) - y * np.sin(c) * np.sin(LAT0))
    lon = (lon + np.pi) % (2 * np.pi) - np.pi
    u = np.nan_to_num((np.degrees(lon) + 180) / 360)
    v = np.nan_to_num((90 - np.degrees(lat)) / 180)
    return u, v, inside, rho


def sample_equirect(img, u, v, inside):
    h, w = img.shape
    m = ndimage.map_coordinates(img, [v * h - 0.5, u * w - 0.5], order=1, mode='wrap')
    return np.where(inside, m, 0)


# ---------------------------------------------------------------- applied markers (rose gold, raised)
def markers_mask():
    img = Image.new('L', (GW, GH), 0)
    d = ImageDraw.Draw(img)
    rad = R + 17 * SS
    for i in range(12):
        if i == 0:
            continue  # XII numeral instead
        a = np.radians(i * 30 - 90)
        cx, cy = CX + rad * np.cos(a), CY + rad * np.sin(a)
        if i % 3 == 0:     # 3, 6, 9: double baton
            L, T = 5.5 * SS, 1.7 * SS
            for off in (-2.6 * SS, 2.6 * SS):
                px, py = -np.sin(a) * off, np.cos(a) * off
                pts = [(-L, -T), (L, -T), (L, T), (-L, T)]
                d.polygon([(cx + px + p * np.cos(a) - q * np.sin(a), cy + py + p * np.sin(a) + q * np.cos(a)) for p, q in pts], fill=255)
        else:              # faceted dots
            r = 3.0 * SS
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    font = ImageFont.truetype('/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf', int(19 * SS))
    tw = d.textlength('XII', font=font)
    d.text((CX - tw / 2, CY - R - 34 * SS), 'XII', font=font, fill=255)
    return np.asarray(img, dtype=np.float64) / 255


# ---------------------------------------------------------------- build
def main(geojson, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    u, v, globe, rho = project()
    land = sample_equirect(land_raster(geojson), u, v, globe)
    # Stamped coasts are crumbly, not vector-smooth: roughen the shoreline and let it break into islets.
    shape0 = land.shape
    crumbs = fbm(shape0, 90, 3, 61) * 0.55 + fbm(shape0, 240, 2, 62) * 0.35
    near_coast = np.exp(-((land - 0.5) / 0.35) ** 2) + np.clip(ndimage.gaussian_filter(land, 3) * (1 - land) * 3, 0, 1)
    land = np.clip((land - 0.5 + crumbs * 0.55 * np.clip(near_coast, 0, 1)) * 3 + 0.5, 0, 1) * globe
    # Real relief: NASA-derived Earth normals integrated to height and high-passed (tools/textures/earth_relief.png)
    relief_src = np.asarray(Image.open(Path(__file__).with_name('earth_relief.png')), dtype=np.float64) / 65535
    earth = sample_equirect(relief_src, u, v, globe)
    land_bin = land > 0.5
    shape = (GH, GW)

    # Distance fields (generation px)
    d_in = ndimage.distance_transform_edt(land_bin)          # inside land, distance to coast
    d_out = ndimage.distance_transform_edt(~land_bin)        # in ocean, distance to coast

    # --- stamped gold, like the photos: a frosted, granular surface (crystalline grains and small nugget clusters)
    # over gentle real terrain, with a short rounded shoulder at the coast. No smooth waves: those read as chrome.
    shoulder = np.clip(d_in / (1.6 * SS), 0, 1)
    shoulder = np.sqrt(shoulder)
    terrain = ndimage.gaussian_filter(np.clip((earth - 0.25) / 0.75, 0, 1), 0.8 * SS)
    terrain = np.clip(terrain + 1.2 * (terrain - ndimage.gaussian_filter(terrain, 3 * SS)), 0, 1)   # crisper ridges
    nuggets = ridged(shape, 70, 3, 12)                              # clusters ~3 px across
    gold_h = (0.12 * shoulder + 0.80 * terrain * shoulder + 0.10 * nuggets * shoulder) * land

    # --- globe rim (half-round raised gold bezel) and applied markers
    r_px = rho * R
    rim_w = 3.5 * SS
    rim_t = np.clip(1 - np.abs(r_px - (R + rim_w)) / rim_w, 0, 1)
    rim_h = np.sqrt(np.clip(1 - (1 - rim_t) ** 2, 0, 1)) * (rim_t > 0)
    mk = markers_mask()
    mk_soft = ndimage.gaussian_filter(mk, 1.6 * SS)
    mk_h = np.clip(mk_soft * 1.6, 0, 1) * mk

    gold_mask = np.clip(land * globe + (rim_t > 0) + mk, 0, 1)
    height_metal = gold_h * 0.9 + rim_h * 0.9 + mk_h * 0.8

    # --- stamped base under the lacquer: very fine sunray-like brushing + soft swell
    base = fbm(shape, 18, 3, 21) * 0.018

    # --- lacquer thickness: hand-applied, pools and thins (flows), thinner where it climbs the coasts
    warp_x = fbm(shape, 4, 3, 31) * 40 * SS
    warp_y = fbm(shape, 4, 3, 32) * 40 * SS
    yy, xx = np.mgrid[0:GH, 0:GW]
    flow = ndimage.map_coordinates(fbm(shape, 9, 4, 33), [np.clip(yy + warp_y, 0, GH - 1), np.clip(xx + warp_x, 0, GW - 1)], order=1)
    meniscus = np.clip(d_out / (4 * SS), 0, 1) ** 0.6
    veins = ridged(shape, 6, 4, 34)
    veins = np.clip((veins - 0.66) / 0.34, 0, 1) ** 1.6               # thin branching streaks of thicker lacquer
    thick_globe = (0.75 + 0.30 * flow + 1.1 * veins) * (0.6 + 0.4 * meniscus)
    space = ~globe
    thick_space = 2.4 + 0.25 * fbm(shape, 5, 3, 41)    # deeper, darker lacquer outside the globe
    thickness = np.where(globe, thick_globe, thick_space)
    thickness = np.where(rim_t > 0, 0.2, thickness)

    # --- height field of the metal (gold relief or base), plus the globe dome
    Rs = R * 1.9                                            # shallow spherical dome
    dome = np.sqrt(np.clip(Rs ** 2 - np.minimum(r_px, R) ** 2, 0, None)) - np.sqrt(Rs ** 2 - R ** 2)
    relief_scale = 13.0 * SS
    metal_h = dome + relief_scale * np.where(gold_mask > 0.5, height_metal, base)

    gy, gx = np.gradient(ndimage.gaussian_filter(metal_h, 0.6))
    # Rounded, not cliff-like: cap the slope softly so no facet turns fully toward the dark floor.
    slope = np.sqrt(gx * gx + gy * gy) + 1e-9
    cap = 0.55 * np.tanh(slope / 0.55) / slope
    n_metal = np.stack([-gx * cap, -gy * cap, np.ones_like(gx)], -1)

    n_metal /= np.linalg.norm(n_metal, axis=-1, keepdims=True)

    # --- gold flakes (paillons) suspended in the dark lacquer outside the globe
    flakes = np.zeros(shape)
    pts = rng.random((150, 2)) * np.array(shape)
    for py, px in pts:
        if globe[int(py), int(px)] or abs(np.hypot(px - CX, py - CY) - (R + 15 * SS)) < 9 * SS:
            continue
        s = rng.uniform(0.5, 1.3) * SS
        k = rng.integers(3, 6)
        ang0 = rng.uniform(0, 6.28)
        poly = [(px + s * (1 + 0.5 * rng.random()) * np.cos(ang0 + j * 6.28 / k), py + s * (1 + 0.5 * rng.random()) * np.sin(ang0 + j * 6.28 / k)) for j in range(k)]
        fimg = Image.new('L', (GW, GH), 0)
        ImageDraw.Draw(fimg).polygon(poly, fill=255)
        m = np.asarray(fimg) > 0
        flakes[m] = rng.uniform(0.15, 1.0)   # random facet seed
    flakes *= (gold_mask < 0.5)

    # --- ambient occlusion: lacquer next to raised gold is shaded a little
    ao = 1 - 0.12 * np.clip(ndimage.gaussian_filter(gold_mask, 1.5 * SS) - gold_mask, 0, 1) * 2

    material = gold_mask
    b_chan = np.where(material > 0.5, np.clip(height_metal, 0, 1), np.clip(thickness / 2.8, 0, 1))

    def down(a):
        return a.reshape(H, SS, W, SS, *a.shape[2:]).mean(axis=(1, 3))

    def enc(v):
        return np.clip(v * 0.5 + 0.5, 0, 1)

    nm = down(n_metal)
    # Crystalline grain: every texel of gold gets its own small tilt, so each one catches a different part of the
    # room — the fine sparkle of frosted gold. (The depth-of-field copy blurs it away toward the rim, as in a macro shot.)
    gold_final = down(gold_mask * globe + mk + (rim_t > 0)).clip(0, 1)[..., None]
    grain_xy = np.random.default_rng(71).normal(0, 1.0, (H, W, 2))
    grain_xy = np.stack([ndimage.gaussian_filter(grain_xy[..., i], 0.7) for i in range(2)], -1)
    grain_xy *= 0.08 / grain_xy.std()                                   # fine crystals: a sparkle, not a texture
    nm[..., 0:2] += grain_xy * (gold_final > 0.5) * down(np.clip(land * globe, 0, 1))[..., None]
    nm /= np.linalg.norm(nm, axis=-1, keepdims=True)
    metal = np.stack([enc(nm[..., 0]), enc(nm[..., 1]), down(b_chan)], -1)
    mat = np.stack([down(material), np.clip(down(flakes) * 1.8, 0, 1), down(np.clip(ao, 0, 1))], -1)
    # Depth of field: blurred copies the shader fades to away from the focus (the centre of the globe).
    metal_dof = np.stack([ndimage.gaussian_filter(metal[..., i], 2.6) for i in range(3)], -1)
    mat_dof = np.stack([ndimage.gaussian_filter(mat[..., i], 2.6) for i in range(3)], -1)
    for name, a in (('world_metal', metal), ('world_mat', mat), ('world_metal_dof', metal_dof), ('world_mat_dof', mat_dof)):
        a = a.copy()
        a[0, 0, :] = 128 / 255          # calibration texel
        Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGB').save(out / f'{name}.png', optimize=True)
    # Preview of masks for checking the projection
    Image.fromarray((down(material) * 255).astype(np.uint8)).save(out / 'preview_material.png')
    print('ok', metal.shape, 'gold coverage', round(float(down(material).mean()), 3))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
