const float GOLDEN_RATIO = 1.61803398875;

// Wind-driven wave spectrum (directional Gerstner-style swell).
const int WAVE_OCTAVES_MAX = 6;
const int WAVE_OCTAVES_MIN = 3;
const float BASE_WAVELENGTH = 110.0;
const float WAVE_STEEPNESS = 0.012;     // amplitude = wavelength * this
const float WAVE_DIR_SPREAD = 2.2;      // radians spread around the wind azimuth
const float GRAVITY = 9.81;

// Raymarching of the height field.
const float MARCH_STEPS = 64.0;
const float BISECTION_STEPS = 4.0;
const float MARCH_STEP_GROWTH = 1.048;
const float MARCH_START_STEP_FRACTION = 0.02;
const float MARCH_MIN_STEP = 0.3;
const float MARCH_MAX_DISTANCE = 6000.0;
const float LOD_OCTAVES_NEAR = 250.0;
const float LOD_OCTAVES_FAR = 2200.0;

// Detail texture usage (contract consts live in common.glsl).
const float MICRO_SLOPE_SCALE = 1.15;
const float DETAIL_FADE_START = 90.0;
const float DETAIL_FADE_END = 700.0;
const float WARP_TILE = 210.0;
const float WARP_STRENGTH = 2.2;

// Shading.
const float SPECULAR_POWER = 340.0;
const float SPECULAR_STRENGTH = 2.6;
const float SSS_STRENGTH = 0.55;
const float FOG_DENSITY = 0.00042;


float hash01(float n) {
  return fract(sin(n) * 43758.5453123);
}


// Sum of the per-octave amplitudes; must mirror the amplitude math of
// waveHeight() exactly. Used for conservative sea bounds and foam mapping.
float waveAmplitudeSeries() {
  float lambda = BASE_WAVELENGTH * waveScale;
  float ampMul = 1.0;
  float sum = 0.0;
  for (int i = 0; i < WAVE_OCTAVES_MAX; i++) {
    sum += lambda * WAVE_STEEPNESS * waveAmplitude * ampMul * (0.35 + windStrength);
    ampMul *= 0.74;
    lambda /= 1.85;
  }
  return sum;
}

// Directional swell: octaves spread stably around the wind direction,
// dispersion-frequency driven phases, crests sharpened by choppiness.
float waveHeight(vec2 pos, float curTime, out float ampSum) {
  float baseAzimuth = atan(windDirection.y, windDirection.x);
  float lambda = BASE_WAVELENGTH * waveScale;
  float ampMul = 1.0;
  float height = 0.0;
  ampSum = 0.0;

  for (int i = 0; i < WAVE_OCTAVES_MAX; i++) {
    float fi = float(i);

    float spread = (hash01(fi * 12.9898 + 4.17) - 0.5) * WAVE_DIR_SPREAD;
    vec2 dir = vec2(cos(baseAzimuth + spread), sin(baseAzimuth + spread));

    float k = TAU / lambda;
    float omega = sqrt(GRAVITY * k) * windSpeed;

    float amp = lambda * WAVE_STEEPNESS * waveAmplitude * ampMul * (0.35 + windStrength);
    ampSum += amp;

    float phase = dot(dir, pos) * k - curTime * omega + hash01(fi * 78.233) * TAU;
    float s = sin(phase);

    // Asymmetric sharpening: narrow crests, broad troughs.
    float sharp = pow(max(s, 0.0), 1.0 + waveChoppiness * 2.5);
    height += amp * (s > 0.0 ? sharp : s);

    ampMul *= 0.74;
    lambda /= 1.85;
  }

  return height;
}

// Organic domain warp sourced from the baked detail map so the swell never
// looks like perfect parallel sine bands.
vec2 warpPos(vec2 p) {
  vec2 w = texture(detailTex, p / WARP_TILE).rg;
  return p + (w - 0.5) * 2.0 * WARP_STRENGTH * (0.5 + waveChoppiness);
}

float heightAt(vec2 p, float curTime) {
  float ampSum;
  float swell = waveHeight(warpPos(p), curTime, ampSum);
  float chop = (texture(detailTex, p / DETAIL_TILE_SIZE).r - 0.5)
      * DETAIL_CHOP_HEIGHT * waveAmplitude;
  return swell + chop;
}

void seaBounds(float ampSum, out float minH, out float maxH) {
  maxH = ampSum * 1.2 + DETAIL_CHOP_HEIGHT * waveAmplitude * 0.5 + WARP_STRENGTH * 0.3;
  minH = -maxH;
}


bool marchOcean(
    vec3 ro, vec3 rd, float jitter, float curTime, float ampSum,
    out vec3 hitPos, out float hitDist) {
  hitPos = vec3(0.0);
  hitDist = 0.0;

  // The camera always stays above the waves; upward rays are pure sky.
  if (rd.y > -0.001) {
    return false;
  }

  float minH;
  float maxH;
  seaBounds(ampSum, minH, maxH);

  float tEnter = (maxH - ro.y) / rd.y;
  float tExit = (minH - ro.y) / rd.y;
  tEnter = max(tEnter, 0.0);
  tExit = min(tExit, MARCH_MAX_DISTANCE);
  if (tEnter >= tExit) {
    return false;
  }

  float stepSize = max(MARCH_MIN_STEP, tEnter * MARCH_START_STEP_FRACTION);
  float t = tEnter + stepSize * jitter;
  float prevT = tEnter;

  for (float i = 0.0; i < MARCH_STEPS; i++) {
    if (t > tExit) {
      return false;
    }

    vec3 samplePos = ro + rd * t;
    float octavesFloat =
        mix(float(WAVE_OCTAVES_MAX), float(WAVE_OCTAVES_MIN),
            smoothstep(LOD_OCTAVES_NEAR, LOD_OCTAVES_FAR, t));
    int octaves = int(octavesFloat + 0.5);
    octaves = octaves < WAVE_OCTAVES_MIN ? WAVE_OCTAVES_MIN : octaves;

    float f = samplePos.y - heightAt(samplePos.xz, curTime);

    if (f < 0.0) {
      float lo = prevT;
      float hi = t;
      for (float b = 0.0; b < BISECTION_STEPS; b++) {
        float mid = (lo + hi) * 0.5;
        vec3 midPos = ro + rd * mid;
        float fm = midPos.y - heightAt(midPos.xz, curTime);
        if (fm < 0.0) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      hitDist = (lo + hi) * 0.5;
      hitPos = ro + rd * hitDist;
      return true;
    }

    prevT = t;
    t += stepSize;
    stepSize *= MARCH_STEP_GROWTH;
  }

  return false;
}


vec3 renderSky(vec3 rd) {
  float upness = clamp(rd.y, 0.0, 1.0);
  vec3 sky = mix(col3(COLOUR_SKY_HORIZON), col3(COLOUR_SKY_ZENITH), pow(upness, 0.55));

  float sunCos = dot(rd, sunDirection);
  float disc = smoothstep(0.99955, 0.99985, sunCos);
  float glowNear = pow(max(sunCos, 0.0), 240.0);
  float glowWide = pow(max(sunCos, 0.0), 6.0);
  sky += col3(COLOUR_SUN) * (disc * 18.0 + glowNear * 1.2 + glowWide * 0.16) * sunIntensity;

  return sky;
}


vec3 waveNormal(vec2 p, float curTime, float distToFrag) {
  float eps = clamp(distToFrag * 0.0022, 0.03, 1.4);
  float hC = heightAt(p, curTime);
  float hX = heightAt(p + vec2(eps, 0.0), curTime);
  float hZ = heightAt(p + vec2(0.0, eps), curTime);

  vec3 n = normalize(vec3(hC - hX, eps, hC - hZ));

  // Micro slopes from the baked map fade out with distance (anti-shimmer).
  float lodFade = 1.0 - smoothstep(DETAIL_FADE_START, DETAIL_FADE_END, distToFrag);
  if (lodFade > 0.003) {
    vec4 tex = texture(detailTex, p / DETAIL_TILE_SIZE);
    vec2 slope = ((tex.gb - 0.5) / DETAIL_SLOPE_ENCODE)
        * (DETAIL_CHOP_HEIGHT / DETAIL_TILE_SIZE);
    slope += ((texture(detailTex, p / (DETAIL_TILE_SIZE * 0.37)).gb - 0.5)
        / DETAIL_SLOPE_ENCODE) * (DETAIL_CHOP_HEIGHT / DETAIL_TILE_SIZE) * 0.45;

    n = normalize(n + vec3(-slope.x, 0.0, -slope.y) * MICRO_SLOPE_SCALE * lodFade);
  }

  return n;
}


vec3 shadeOcean(vec3 pos, vec3 rd, float dist, float curTime, float ampSum) {
  vec3 v = -rd;
  vec3 n = waveNormal(pos.xz, curTime, dist);

  float fresnel = fresnelSchlick(max(dot(n, v), 0.0), 0.022);

  vec3 reflDir = reflect(rd, n);
  reflDir.y = abs(reflDir.y);
  vec3 reflection = renderSky(reflDir);

  // Foam: baked mask modulated by crest height and local steepness.
  float steep = saturate(1.0 - n.y);
  vec4 detailSample = texture(detailTex, pos.xz / DETAIL_TILE_SIZE);
  float crestFactor = saturate(pos.y / max(ampSum, 0.001) * 0.5 + 0.5);
  float foamMask =
      detailSample.a * (0.35 + 0.65 * crestFactor) + smoothstep(0.10, 0.32, steep) * 0.55;
  float foam = saturate(smoothstep(
      0.72 - foamAmount * 0.38, 1.02 - foamAmount * 0.25, foamMask));

  // Water body: deep colour plus subsurface glow on sunlit crests.
  float sunSide = max(dot(n, sunDirection), 0.0);
  vec3 body = col3(COLOUR_WATER_DEEP);
  body += col3(COLOUR_WATER_SUBSURFACE)
      * (pow(sunSide, 2.0) * 0.45 + crestFactor * 0.75)
      * SSS_STRENGTH
      * clamp(sunDirection.y * 2.2, 0.06, 1.0)
      * sunIntensity;

  vec3 waterColour = mix(body, reflection, fresnel);

  // Sun glitter path; broadens with distance as micro-normals fade.
  float specPower = mix(SPECULAR_POWER, 48.0,
      smoothstep(DETAIL_FADE_START, DETAIL_FADE_END, dist));
  vec3 halfVec = normalize(sunDirection + v);
  float spec = pow(max(dot(n, halfVec), 0.0), specPower) * SPECULAR_STRENGTH;
  waterColour += col3(COLOUR_SUN) * spec * sunIntensity * (1.0 - fresnel * 0.5);

  vec3 foamColour = col3(COLOUR_FOAM)
      * (0.32 + 0.68 * clamp(sunDirection.y * 2.5 + 0.25, 0.0, 1.0))
      * sunIntensity;

  vec3 colour = mix(waterColour, foamColour, foam);

  // Distance haze towards the sky at the horizon.
  vec3 fogColour = renderSky(normalize(vec3(rd.x, 0.0, rd.z)));
  float fog = 1.0 - exp(-dist * FOG_DENSITY);
  colour = mix(colour, fogColour, saturate(fog));

  return colour;
}


void main() {
  vec2 pixelCoords = (vUvs - 0.5) * resolution;
  float curTime = time;

  mat3 camera = MakeCamera(cameraOrigin, cameraTarget, vec3(0.0, 1.0, 0.0));

  vec2 rayCoords = (2.0 * (gl_FragCoord.xy - 0.5) - resolution) / resolution.y;
  vec3 rd = normalize(camera * vec3(rayCoords, 2.0));
  vec3 ro = cameraOrigin;

  vec2 aspect = vec2(1.0, resolution.y / resolution.x);
  float jitter =
      texture2D(blueNoise, (pixelCoords / resolution + 0.5) * aspect * (resolution.x / 32.0)).x;
  jitter = fract(jitter + float(frame % 32) * GOLDEN_RATIO);

  float ampSum = waveAmplitudeSeries();

  vec3 colour;

  vec3 hitPos;
  float hitDist;
  if (marchOcean(ro, rd, jitter, curTime, ampSum, hitPos, hitDist)) {
    colour = shadeOcean(hitPos, rd, hitDist, curTime, ampSum);
  } else {
    colour = renderSky(rd);
  }

#ifdef USE_OKLAB
  colour = oklabToRGB(colour);
  colour = ACESToneMap(colour);
  // Store the tone-mapped result encoded in OkLab: the composite pass
  // decodes it with oklabToRGB (same convention as shader-clouds).
  colour = col3(colour);
#else
  colour = ACESToneMap(colour);
#endif

  gl_FragColor = vec4(colour, 1.0);
}
