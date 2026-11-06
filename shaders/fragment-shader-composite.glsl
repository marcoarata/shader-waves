

void main() {
  // Debug views bypass the tonemapping pipeline entirely so the raw baked
  // textures are displayed faithfully.
  if (debugMode > 0.5) {
    vec4 tex = texture2D(detailTex, vUvs);
    vec3 c;
    if (debugMode < 1.5) {
      // Detail map: height in gray, slopes tinted red/green.
      vec2 slope = (tex.gb - 0.5) * 2.0;
      c = vec3(tex.r) + vec3(abs(slope.x), 0.0, abs(slope.y)) * 0.3;
    } else if (debugMode < 2.5) {
      // Foam mask.
      c = vec3(tex.a);
    } else {
      // Decoded micro-normal preview.
      vec2 slopeWorld = ((tex.gb - 0.5) / DETAIL_SLOPE_ENCODE)
          * (DETAIL_CHOP_HEIGHT / DETAIL_TILE_SIZE);
      vec3 n = normalize(vec3(-slopeWorld.x, 1.0, -slopeWorld.y));
      c = n * 0.5 + 0.5;
    }
    gl_FragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
    return;
  }

  vec4 colour = texture2D(frameTexture, vUvs);

#ifdef USE_OKLAB
  colour.xyz = oklabToRGB(colour.xyz);
#endif

  // Vignette
  colour.xyz *= vignette(vUvs);
  colour.xyz = pow(saturate3(colour.xyz), vec3(1.0 / 2.2));

  gl_FragColor = vec4(colour.xyz, 1.0);
}
