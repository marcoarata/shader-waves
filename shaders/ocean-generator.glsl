uniform float zLevel; // Unused for the 2D bake; kept so the baker API stays uniform.


// Tileable gradient noise: lattice hashes are wrapped with mod() so the noise
// repeats seamlessly every `tileLength` units (same technique as the
// Perlin-Worley generator of shader-clouds).

vec2 hash2_Tile(vec2 cell, float tileLength, float seed) {
  vec2 p = mod(cell, vec2(tileLength));
  vec2 q = vec2(
      dot(p, vec2(127.1, 311.7)),
      dot(p, vec2(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(q + seed) * 43758.5453123);
}

float gradientNoiseTile(vec2 p, float tileLength, float seed) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);

  return mix(
      mix(dot(hash2_Tile(i + vec2(0.0, 0.0), tileLength, seed), f - vec2(0.0, 0.0)),
          dot(hash2_Tile(i + vec2(1.0, 0.0), tileLength, seed), f - vec2(1.0, 0.0)), u.x),
      mix(dot(hash2_Tile(i + vec2(0.0, 1.0), tileLength, seed), f - vec2(0.0, 1.0)),
          dot(hash2_Tile(i + vec2(1.0, 1.0), tileLength, seed), f - vec2(1.0, 1.0)), u.x), u.y);
}

float oceanFBM(vec2 uv, float baseCells, float seed) {
  float total = 0.0;
  float amplitude = 0.5;
  float normalization = 0.0;

  vec2 p = uv * baseCells;
  float cells = baseCells;
  for (int i = 0; i < 5; ++i) {
    total += gradientNoiseTile(p, cells, seed + float(i) * 17.31) * amplitude;
    normalization += amplitude;
    amplitude *= 0.55;
    p *= 2.0;
    cells *= 2.0;
  }

  return total / normalization; // roughly [-1, 1]
}


// Height field in texture space. uv in [0, 1] covers exactly one tile.
float oceanHeight(vec2 uv) {
  return oceanFBM(uv, 8.0, 3.7) * 0.5 + 0.5;
}


void main() {
  const float EPSILON = 1.0 / 512.0;

  vec2 uv = vUvs;

  float h = oceanHeight(uv);

  // Forward differences in tileable space keep the derivatives seamless.
  float dhdx = (oceanHeight(uv + vec2(EPSILON, 0.0)) - h) / EPSILON;
  float dhdz = (oceanHeight(uv + vec2(0.0, EPSILON)) - h) / EPSILON;

  // Encode slopes to [0, 1]; typical |slope| stays below ~8.
  float sx = clamp(dhdx * DETAIL_SLOPE_ENCODE + 0.5, 0.0, 1.0);
  float sz = clamp(dhdz * DETAIL_SLOPE_ENCODE + 0.5, 0.0, 1.0);

  // Foam mask: crest heights broken up by streaky ripples elongated along
  // the wind axis (+x in texture space).
  vec2 streakUv = vec2(uv.x, uv.y * 3.0);
  float streaks = oceanFBM(streakUv, 10.0, 91.42) * 0.5 + 0.5;
  float breakup = oceanHeight(fract(uv + vec2(0.37, 0.71)));

  float foam = smoothstep(0.58, 0.92, h + streaks * 0.18 + breakup * 0.12);

  gl_FragColor = vec4(h, sx, sz, foam);
}
