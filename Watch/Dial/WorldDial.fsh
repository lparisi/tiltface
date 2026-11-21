// World face dial: stamped rose-gold relief and blue lacquer, reflecting a real photographic environment
// that turns with the wrist. SpriteKit fragment shader (GLSL ES, translated to Metal by SpriteKit).
// Keep in step with tools/textures/preview_shader.py (CPU reference used to tune the look).
// SpriteKit's translation rejects file-scope constants and `out` parameters, and uniforms are only visible in main.
//
// Uniforms
//   u_metal, u_metal_dof   RG metal normal xy, B relief height (gold) / lacquer thickness / 2.8 (sharp, blurred)
//   u_mat, u_mat_dof       R gold mask, G (unused), B ambient occlusion (sharp, blurred)
//   u_env                  three stacked log-encoded equirect maps (sharp / satin / soft), 256 x 384
//   u_gravity              gravity in the watch frame (x right, y toward 12, z out of the screen), unit length
//   u_tex                  dial texture size in texels (432, 528)
//   u_view                 visible screen size in texels

float smoothstep01(float e0, float e1, float x) {
    float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

vec3 toSRGB(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

vec3 decodeNormal(vec2 enc) {
    vec2 n = enc * 2.0 - 1.0;
    return normalize(vec3(n, sqrt(clamp(1.0 - dot(n, n), 0.05, 1.0))));
}

// Where direction r lands in the stacked environment map. level 0 sharp, 1 satin, 2 soft.
// U/F/Rt: the room's up, forward and right. (Uniforms are only visible in main, so the read happens there.)
vec2 envUV(vec3 r, float level, vec3 U, vec3 F, vec3 Rt) {
    float x = dot(r, Rt);
    float y = dot(r, U);
    float z = dot(r, F);
    float u = fract(atan(x, z) / 6.2831853 + 0.5 + 0.10);
    float v = clamp(acos(clamp(y, -1.0, 1.0)) / 3.1415927, 0.5 / 128.0, 1.0 - 0.5 / 128.0);
    return vec2(u, 1.0 - (level + v) / 3.0);
}

// The room as a jeweller would light it for the gold: same light and shadow, most of the colour removed.
vec3 neutral(vec3 e) {
    float lum = dot(e, vec3(0.2126, 0.7152, 0.0722));
    return mix(e, vec3(lum), 0.7);
}

// Log-encoded texel -> radiance.
vec3 envDecode(vec3 c, float lin) {
    if (lin > 0.5) { c = toSRGB(c); }
    return exp2(c * 8.0056) - vec3(1.0);       // log2(1 + 256)
}

void main() {
    vec3 GOLD = vec3(1.00, 0.80, 0.50);        // pale champagne gold reflectance
    vec3 SIGMA = vec3(3.4, 4.2, 0.55);         // ultramarine lacquer: absorbs green most, a little red passes
    vec3 PIGMENT = vec3(0.030, 0.018, 0.21);   // light scattered back by the violet-blue pigment

    vec2 screen = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y) * u_tex;

    // Calibration: texel (0,0) of every map is 128/255. If it reads ~0.22 the upload was linearised.
    float probe = texture2D(u_metal, vec2(0.5 / u_tex.x, 1.0 - 0.5 / u_tex.y)).r;
    float lin = probe < 0.35 ? 1.0 : 0.0;

    // Domed sapphire crystal: near the bezel the dial is seen magnified, pulled inward.
    vec2 cs = screen - u_tex * 0.5;
    vec2 halfSize = u_view * 0.5;
    float rad = 0.2 * min(u_view.x, u_view.y);
    vec2 qe = abs(cs) - halfSize + rad;
    float dEdge = -(length(max(qe, vec2(0.0))) + min(max(qe.x, qe.y), 0.0) - rad);
    vec2 sgn = vec2(cs.x < 0.0 ? -1.0 : 1.0, cs.y < 0.0 ? -1.0 : 1.0);
    vec2 nEdge = qe.x > qe.y ? vec2(sgn.x, 0.0) : vec2(0.0, sgn.y);
    if (qe.x > 0.0 && qe.y > 0.0) { nEdge = normalize(qe) * sgn; }
    float band = 0.10 * min(u_view.x, u_view.y);
    float tEdge = clamp(1.0 - dEdge / band, 0.0, 1.0);
    vec2 px = screen - nEdge * band * 0.30 * tEdge * tEdge * tEdge;
    vec2 uv = vec2(px.x / u_tex.x, 1.0 - px.y / u_tex.y);

    // Depth of field: sharp at the centre of the globe, softer toward the rim and the bezel.
    vec2 c = px - u_tex * 0.5;
    float R = 0.43 * u_tex.x;
    float lc = length(c);
    float dof = clamp(smoothstep01(0.75, 1.25, lc / R) * 0.55 + tEdge, 0.0, 1.0);
    vec3 m = mix(texture2D(u_metal, uv).rgb, texture2D(u_metal_dof, uv).rgb, dof);
    vec3 q = mix(texture2D(u_mat, uv).rgb, texture2D(u_mat_dof, uv).rgb, dof);
    if (lin > 0.5) { m = toSRGB(m); q = toSRGB(q); }

    vec3 nMetal = decodeNormal(m.rg);
    float hgt = m.b;
    float goldM = q.r;
    float ao = q.b;

    vec3 p = vec3(px, 0.0);
    vec3 eye = vec3(u_tex.x * 0.5, u_tex.y * 0.5, 2.4 * u_tex.x);
    vec3 v = normalize(eye - p);

    // The room: up is opposite to gravity (device y points to 12, screen y points down).
    vec3 U = normalize(vec3(-u_gravity.x, u_gravity.y, -u_gravity.z));
    vec3 F = vec3(0.0, 0.0, 1.0) - U * U.z;
    if (length(F) < 0.15) {
        vec3 twelve = vec3(0.0, -1.0, 0.0);
        F += 0.2 * (twelve - U * dot(U, twelve));
    }
    F = normalize(F);
    vec3 Rt = cross(U, F);

    // Lacquer top surface: a shallow polished dome over the globe, flat elsewhere.
    float Rs = R * 1.9;
    float rr = min(lc, R);
    vec3 nCoat = lc < R ? normalize(vec3(c * (rr / max(lc, 0.001)), sqrt(Rs * Rs - rr * rr))) : vec3(0.0, 0.0, 1.0);

    // Gold: a frosted, granular surface (per-texel grain is baked in the normals); each grain mirrors a different
    // part of the room, tinted by the gold (twice in the cavities).
    float nov = clamp(dot(nMetal, v), 0.001, 1.0);
    vec3 r = 2.0 * nov * nMetal - v;
    vec3 fres = GOLD + (vec3(1.0) - GOLD) * pow(1.0 - nov, 5.0);
    float cavity = clamp(0.8 + 0.6 * hgt, 0.0, 1.0);
    vec3 refl = neutral(envDecode(texture2D(u_env, envUV(r, 0.0, U, F, Rt)).rgb, lin)) * 0.35
              + neutral(envDecode(texture2D(u_env, envUV(r, 1.0, U, F, Rt)).rgb, lin)) * 0.65;
    vec3 gold = fres * refl * (vec3(cavity) + (1.0 - cavity) * GOLD) * 1.1;

    // Blue lacquer: glassy surface over a bright metal base; light is coloured by absorption on the way through.
    float ncv = clamp(dot(nCoat, v), 0.001, 1.0);
    vec3 rc = 2.0 * ncv * nCoat - v;
    float fc = 0.04 + 0.96 * pow(1.0 - ncv, 5.0);
    vec3 coat = fc * mix(envDecode(texture2D(u_env, envUV(rc, 0.0, U, F, Rt)).rgb, lin), envDecode(texture2D(u_env, envUV(rc, 1.0, U, F, Rt)).rgb, lin), 0.7 * dof);
    vec3 rb = 2.0 * dot(nMetal, v) * nMetal - v;
    float path = hgt * 2.8 * (0.5 + 0.5 / max(ncv, 0.25));
    vec3 trans = exp(-SIGMA * path);
    vec3 base = 0.75 * envDecode(texture2D(u_env, envUV(rb, 2.0, U, F, Rt)).rgb, lin);
    vec3 amb = envDecode(texture2D(u_env, envUV(nCoat, 2.0, U, F, Rt)).rgb, lin);
    vec3 pigment = PIGMENT * (0.4 + 0.6 * clamp(dot(amb, vec3(1.0 / 3.0)), 0.0, 3.0));
    vec3 body = (base * trans + pigment) * (1.0 - fc) * ao;

    vec3 col = mix(body + coat, gold, goldM);

    // Crystal edge: darker toward the bezel, plus the bevel of the sapphire mirroring the room.
    col *= 1.0 - 0.45 * tEdge * tEdge * tEdge;
    vec3 nb = normalize(vec3(nEdge * (tEdge * 1.1), 1.0));
    vec3 rb2 = 2.0 * dot(nb, v) * nb - v;
    col += tEdge * tEdge * 0.08 * envDecode(texture2D(u_env, envUV(rb2, 0.0, U, F, Rt)).rgb, lin);

    col = vec3(1.0) - exp(-col * 1.3);
    col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 1.15));
    if (lin > 0.5) { col = toLinear(col); }
    gl_FragColor = vec4(col, 1.0);
}
