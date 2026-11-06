#define PI 3.14159265359
#define TAU 6.28318530718


float saturate(float x) {
  return clamp(x, 0.0, 1.0);
}

vec3 saturate3(vec3 x) {
  return clamp(x, vec3(0.0), vec3(1.0));
}


float linearstep(float minValue, float maxValue, float v) {
  return clamp((v - minValue) / (maxValue - minValue), 0.0, 1.0);
}

float inverseLerp(float minValue, float maxValue, float v) {
  return (v - minValue) / (maxValue - minValue);
}

float remap(float v, float inMin, float inMax, float outMin, float outMax) {
  float t = inverseLerp(inMin, inMax, v);
  return mix(outMin, outMax, t);
}

float smootherstep(float edge0, float edge1, float x) {
  x = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

float fresnelSchlick(float cosTheta, float f0) {
  return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}


mat3 MakeCamera(vec3 ro, vec3 rd, vec3 ru) {
	vec3 z = normalize(rd - ro);
	vec3 cp = ru;
	vec3 x = normalize(cross(z, cp));
	vec3 y = cross(x, z);
  return mat3(x, y, z);
}


/////////////////////////////////////////////////////////////////////////
//
// Shared ocean detail texture contract.
// Must stay in sync with shaders/ocean-generator.glsl.
//
/////////////////////////////////////////////////////////////////////////

// World units covered by one repeat of the baked detail texture.
const float DETAIL_TILE_SIZE = 64.0;
// World units of vertical displacement represented by the full R range.
const float DETAIL_CHOP_HEIGHT = 1.35;
// Slopes are stored as slopeUV * DETAIL_SLOPE_ENCODE + 0.5.
const float DETAIL_SLOPE_ENCODE = 0.06;


vec3 vignette(vec2 uvs) {
  float v1 = smoothstep(0.5, 0.3, abs(uvs.x - 0.5));
  float v2 = smoothstep(0.5, 0.3, abs(uvs.y - 0.5));
  float v = v1 * v2;
  v = pow(v, 0.25);
  v = remap(v, 0.0, 1.0, 0.4, 1.0);
  return vec3(v);
}


/////////////////////////////////////////////////////////////////////////
//
// ToneMapping Operators
//
/////////////////////////////////////////////////////////////////////////
vec3 ACESToneMap(vec3 color){
	mat3 m1 = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
	);
	mat3 m2 = mat3(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
	);
	vec3 v = m1 * color;
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return saturate3(m2 * (a / b));
}
