
precision highp float;
precision highp sampler2D;
precision highp int;

varying vec2 vUvs;
uniform vec2 resolution;
uniform float time;
uniform int frame;

uniform vec2 frameResolution;
uniform sampler2D frameTexture;

uniform sampler2D blueNoise;

// Baked tileable ocean detail: R = chop height, G/B = slopes, A = foam mask.
uniform sampler2D detailTex;

// Camera (set from JS, orbit controls).
uniform vec3 cameraOrigin;
uniform vec3 cameraTarget;

// Sun.
uniform vec3 sunDirection;
uniform float sunIntensity;

// Wind system (set from JS).
uniform vec2 windDirection;   // normalized xz
uniform float windStrength;
uniform float windSpeed;
uniform float foamAmount;

// Wave tuning (exposed in the GUI).
uniform float waveAmplitude;
uniform float waveChoppiness;
uniform float waveScale;

// Debug views: 0 = off, 1 = detail texture, 2 = foam mask, 3 = normals.
uniform float debugMode;


// Sea & sky palette.
vec3 COLOUR_WATER_DEEP = vec3(0.006, 0.10, 0.16);
vec3 COLOUR_WATER_SUBSURFACE = vec3(0.05, 0.42, 0.38);
vec3 COLOUR_FOAM = vec3(0.92, 0.96, 0.97);
vec3 COLOUR_SKY_ZENITH = vec3(0.09, 0.30, 0.58);
vec3 COLOUR_SKY_HORIZON = vec3(0.64, 0.76, 0.85);
vec3 COLOUR_SUN = vec3(1.0, 0.86, 0.62);


#define USE_OKLAB
