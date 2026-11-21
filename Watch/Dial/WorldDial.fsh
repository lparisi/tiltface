// World face dial: rose-gold stamped relief and hand-applied blue lacquer, lit by the room around the wrist.
// SpriteKit fragment shader (GLSL ES, translated to Metal by SpriteKit). Keep in step with tools/textures/preview_shader.py.
//
// Uniforms
//   u_metal    world_metal.png  RG metal normal xy, B relief height (gold) / lacquer thickness / 2.8
//   u_mat      world_mat.png    R gold mask, G gold-flake seed, B ambient occlusion
//   u_gravity  gravity in the watch frame (x right, y toward 12, z out of the screen), unit length
//   u_tex      texture size in texels (432, 528)
//   u_view     visible screen size in texels (the sprite is aspect-filled, so it can be smaller than u_tex)
//
// Lacquer model: a glossy clear surface (Schlick fresnel, mirror of the room's lights) over a bright stamped metal
// base. Light passes through the coloured lacquer twice, so the blue deepens with thickness and viewing angle
// (Beer–Lambert), and glows where the base reflects a light. Rose gold is a rough metal tinted by its colour.

const vec3 GOLD = vec3(1.00, 0.70, 0.47);
const vec3 SIGMA = vec3(5.0, 3.1, 0.38);
const vec3 PIGMENT = vec3(0.010, 0.028, 0.20);

float smoothstep01(float e0, float e1, float x) {
    float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

vec3 envMetal(vec3 r, vec3 key, vec3 fill, float rough) {
    float k = clamp(dot(r, key), 0.0, 1.0);
    float f = clamp(dot(r, fill), 0.0, 1.0);
    float e = 6.0 + (1.0 - rough) * 60.0;
    float v = 0.22 + 0.18 * clamp(r.z, 0.0, 1.0) + 1.0 * pow(k, 5.0) + 3.6 * pow(k, e) + 6.0 * pow(k, e * 6.0)
            + 0.9 * pow(f, e * 0.5);
    return vec3(v);
}

vec3 envCoat(vec3 r, vec3 key, vec3 fill) {
    float k = dot(r, key);
    float f = dot(r, fill);
    float box = smoothstep01(0.986, 0.993, k) * 14.0 + pow(clamp(k, 0.0, 1.0), 40.0) * 1.2;
    float win = smoothstep01(0.965, 0.978, f) * 6.0;
    float room = 0.05 + 0.10 * clamp(r.z, 0.0, 1.0);
    return vec3(box + win + room);
}

vec3 decodeNormal(vec2 enc) {
    vec2 n = enc * 2.0 - 1.0;
    return normalize(vec3(n, sqrt(clamp(1.0 - dot(n, n), 0.05, 1.0))));
}

// sRGB encode, for undoing a linearised upload and for writing to a linear target.
vec3 toSRGB(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// Domed sapphire crystal: near the bezel the dial is seen magnified, pulled inward. Returns the edge factor t (0..1)
// and writes the distorted sample position and the outward edge normal.
float crystal(vec2 screen, out vec2 px, out vec2 nEdge) {
    vec2 c = screen - u_tex * 0.5;
    vec2 halfSize = u_view * 0.5;
    float rad = 0.2 * min(u_view.x, u_view.y);
    vec2 q = abs(c) - halfSize + rad;
    float d = -(length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad);
    vec2 sgn = vec2(c.x < 0.0 ? -1.0 : 1.0, c.y < 0.0 ? -1.0 : 1.0);
    if (q.x > 0.0 && q.y > 0.0) {
        nEdge = normalize(q) * sgn;
    } else if (q.x > q.y) {
        nEdge = vec2(sgn.x, 0.0);
    } else {
        nEdge = vec2(0.0, sgn.y);
    }
    float band = 0.10 * min(u_view.x, u_view.y);
    float t = clamp(1.0 - d / band, 0.0, 1.0);
    px = screen - nEdge * band * 0.30 * t * t * t;
    return t;
}

void main() {
    // SpriteKit texture coordinates start bottom-left; the maps are authored top-down.
    vec2 screen = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y) * u_tex;
    vec2 px;
    vec2 nEdge;
    float tEdge = crystal(screen, px, nEdge);
    vec2 uv = vec2(px.x / u_tex.x, 1.0 - px.y / u_tex.y);

    // Calibration: texel (0,0) is 128/255. If it reads ~0.22 the upload was linearised.
    float probe = texture2D(u_metal, vec2(0.5 / u_tex.x, 1.0 - 0.5 / u_tex.y)).r;
    bool linearised = probe < 0.35;

    vec3 m = texture2D(u_metal, uv).rgb;
    vec3 q = texture2D(u_mat, uv).rgb;
    if (linearised) { m = toSRGB(m); q = toSRGB(q); }

    vec3 nMetal = decodeNormal(m.rg);
    float hgt = m.b;
    float goldM = q.r;
    float flake = q.g;
    float ao = q.b;

    // Viewer above the dial centre (perspective, so highlights sit in one place and travel with the light).
    vec3 p = vec3(px, 0.0);
    vec3 eye = vec3(u_tex.x * 0.5, u_tex.y * 0.5, 2.4 * u_tex.x);
    vec3 v = normalize(eye - p);

    // Room lights: "up" is opposite to gravity; device y points to 12, screen y points down.
    vec3 up = vec3(-u_gravity.x, u_gravity.y, -u_gravity.z);
    vec3 key = normalize(up + vec3(-0.30, -0.42, 0.0));
    vec3 fill = normalize(up + vec3(0.95, 0.10, -0.15));

    // Lacquer top surface: a shallow polished dome over the globe, flat elsewhere.
    vec2 c = px - u_tex * 0.5;
    float R = 0.43 * u_tex.x;
    float Rs = R * 1.9;
    float rr = min(length(c), R);
    vec3 nCoat = length(c) < R ? normalize(vec3(c * (rr / max(length(c), 0.001)), sqrt(Rs * Rs - rr * rr))) : vec3(0.0, 0.0, 1.0);

    // Rose gold
    float nov = clamp(dot(nMetal, v), 0.001, 1.0);
    vec3 r = 2.0 * nov * nMetal - v;
    vec3 fres = GOLD + (vec3(1.0) - GOLD) * pow(1.0 - nov, 5.0);
    vec3 gold = fres * envMetal(r, key, fill, 0.55) * (0.72 + 0.28 * hgt);

    // Blue lacquer
    float ncv = clamp(dot(nCoat, v), 0.001, 1.0);
    vec3 rc = 2.0 * ncv * nCoat - v;
    float fc = 0.04 + 0.96 * pow(1.0 - ncv, 5.0);
    vec3 coat = fc * envCoat(rc, key, fill);
    vec3 rb = 2.0 * dot(nMetal, v) * nMetal - v;
    float thick = hgt * 2.8;
    float path = thick * (0.5 + 0.5 / max(ncv, 0.25));
    vec3 trans = exp(-SIGMA * path);
    vec3 base = 0.9 * envMetal(rb, key, fill, 0.2);
    vec3 pigment = PIGMENT * (0.35 + 0.65 * clamp(dot(nCoat, key), 0.0, 1.0));
    vec3 body = (base * trans + pigment) * (1.0 - fc) * ao;

    // Gold flakes in the lacquer, each with its own facet: they glint one at a time as the wrist turns.
    if (flake > 0.02) {
        float ang = flake * 6.2831 * 7.0;
        vec3 nf = normalize(vec3(cos(ang) * 0.45, sin(ang) * 0.45, 1.0));
        vec3 rf = 2.0 * dot(nf, v) * nf - v;
        vec3 glint = GOLD * pow(clamp(dot(rf, key), 0.0, 1.0), 90.0) * 9.0 + GOLD * 0.10;
        body = body * 0.4 + glint;
    }

    vec3 lacquer = body + coat;
    vec3 col = mix(lacquer, gold, goldM);

    // Crystal edge: darker toward the bezel, plus the bevel of the sapphire catching the light.
    col *= 1.0 - 0.45 * tEdge * tEdge * tEdge;
    vec3 nb = normalize(vec3(nEdge * (tEdge * 1.1), 1.0));
    vec3 rb2 = 2.0 * dot(nb, v) * nb - v;
    col += tEdge * tEdge * 0.06 * envCoat(rb2, key, fill);
    col = vec3(1.0) - exp(-col * 1.2);
    col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 1.15));
    if (linearised) { col = toLinear(col); }
    gl_FragColor = vec4(col, 1.0);
}
