import * as THREE from 'three';
import { loadFragmentShader, loadVertexShader } from './glsl-loader.js';

// Bakes a fragment shader into a single tileable 2D texture by rendering one
// full-screen pass and packing the pixels into a THREE.DataTexture.
export class TextureGenerator {
  constructor(renderer, options) {
    this.threejs_ = renderer;
    this.resolution_ = options.resolution;
    this.fragmentShaderPath_ = options.fragmentShaderPath;
    this.uniforms_ = options.uniforms ?? {};

    this.onLoad = () => {};
    this.textures_ = {};
  }

  async init_() {
    const vertexShader = await loadVertexShader();
    const fragmentShader = await loadFragmentShader(this.fragmentShaderPath_);

    this.material_ = new THREE.ShaderMaterial({
      uniforms: this.uniforms_,
      vertexShader: vertexShader,
      fragmentShader: fragmentShader,
    });

    this.scene_ = new THREE.Scene();
    this.camera_ = new THREE.OrthographicCamera(0, 1, 1, 0, 0.1, 1000);
    this.camera_.position.set(0, 0, 1);

    const geometry = new THREE.PlaneGeometry(1, 1);
    const plane = new THREE.Mesh(geometry, this.material_);
    plane.position.set(0.5, 0.5, 0);
    this.scene_.add(plane);

    this.rt_ = new THREE.WebGLRenderTarget(this.resolution_, this.resolution_);
  }

  get Info() {
    return this.textures_;
  }

  Load() {
    const X = this.resolution_;
    const Y = this.resolution_;

    this.threejs_.setRenderTarget(this.rt_);
    this.threejs_.render(this.scene_, this.camera_);

    const pixelBuffer = new Uint8Array(X * Y * 4);
    this.threejs_.readRenderTargetPixels(this.rt_, 0, 0, X, Y, pixelBuffer);
    this.threejs_.setRenderTarget(null);

    const texture = new THREE.DataTexture(pixelBuffer, X, Y, THREE.RGBAFormat, THREE.UnsignedByteType);
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.magFilter = THREE.LinearFilter;
    texture.wrapS = THREE.RepeatWrapping;
    texture.wrapT = THREE.RepeatWrapping;
    texture.anisotropy = this.threejs_.capabilities.getMaxAnisotropy();
    texture.generateMipmaps = true;
    texture.needsUpdate = true;

    this.textures_['diffuse'] = {
      textures: [pixelBuffer],
      atlas: texture,
    };

    this.onLoad();
  }
}

// Bakes the tileable ocean detail map (chop height, slopes, foam mask).
export function createOceanDetailGenerator(renderer) {
  return new TextureGenerator(renderer, {
    resolution: 512,
    fragmentShaderPath: 'ocean-generator.glsl',
  });
}
