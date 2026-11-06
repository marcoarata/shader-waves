import * as THREE from 'three';
import GUI from 'lil-gui';
import { loadFragmentShader, loadVertexShader } from './glsl-loader.js';
import { createOceanDetailGenerator } from './texture-baker.js';

// Initial orbit framing: camera over open water looking towards the horizon.
const ORBIT_INITIAL = {
  target: new THREE.Vector3(0.0, 1.0, 0.0),
  radius: 330.0,
  yaw: 0.35,
  pitch: 0.14,
};

// Sea-state safety clamps: keep the camera comfortably above the waves.
const PITCH_MIN = 0.05;
const PITCH_MAX = 1.35;
const RADIUS_MIN = 150.0;
const RADIUS_MAX = 1600.0;

const SUN_INITIAL = new THREE.Vector3();

class App {
  constructor() {
    this.orbitCurrent_ = {
      target: ORBIT_INITIAL.target.clone(),
      radius: ORBIT_INITIAL.radius,
      yaw: ORBIT_INITIAL.yaw,
      pitch: ORBIT_INITIAL.pitch,
    };
    this.orbitDesired_ = {
      target: ORBIT_INITIAL.target.clone(),
      radius: ORBIT_INITIAL.radius,
      yaw: ORBIT_INITIAL.yaw,
      pitch: ORBIT_INITIAL.pitch,
    };
    this.sunParams_ = { azimuth: 155, elevation: 24, intensity: 1.0 };
    this.windParams_ = { azimuth: -70, strength: 0.55, speed: 1.0 };
    this.animParams_ = { timeSpeed: 1.0 };

    // Shared between the ocean material and the composite material so a
    // single GUI control drives both passes.
    this.debugUniforms_ = {
      debugMode: { value: 0.0 },
    };
  }

  async initialize() {
    this.threejs_ = new THREE.WebGLRenderer();
    this.threejs_.outputEncoding = THREE.LinearEncoding;
    document.body.appendChild(this.threejs_.domElement);

    window.addEventListener('resize', () => {
      this.onWindowResize_();
    }, false);

    this.scene_ = new THREE.Scene();
    this.finalScene_ = new THREE.Scene();

    this.camera_ = new THREE.OrthographicCamera(0, 1, 1, 0, 0.1, 1000);
    this.camera_.position.set(0, 0, 1);

    this.rtScale_ = 0.5;
    this.rtParams_ = {
      type: THREE.HalfFloatType,
      magFilter: THREE.LinearFilter,
      minFilter: THREE.LinearMipmapLinearFilter,
      anisotropy: this.threejs_.capabilities.getMaxAnisotropy(),
      generateMipmaps: true,
    };
    this.rt_ = new THREE.WebGLRenderTarget(
        window.innerWidth * this.rtScale_, window.innerHeight * this.rtScale_, this.rtParams_);

    await this.setupProject_();
    this.setupInput_();
    this.setupGui_();
  }

  async setupProject_() {
    const vertexShader = await loadVertexShader();

    const compositeMaterial = new THREE.ShaderMaterial({
      uniforms: {
        resolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
        frameResolution: { value: new THREE.Vector2(this.rt_.width, this.rt_.height) },
        time: { value: 0.0 },
        frameTexture: { value: null },
        detailTex: { value: null },
        debugMode: this.debugUniforms_.debugMode,
      },
      vertexShader: vertexShader,
      fragmentShader: await loadFragmentShader('fragment-shader-composite.glsl'),
    });

    this.compositeMaterial_ = compositeMaterial;
    const compositeGeometry = new THREE.PlaneGeometry(1, 1);
    const compositePlane = new THREE.Mesh(compositeGeometry, compositeMaterial);
    compositePlane.position.set(0.5, 0.5, 0);
    this.finalScene_.add(compositePlane);

    const loader = new THREE.TextureLoader();
    const blueNoise = loader.load('./textures/HDR_L_0.png');

    blueNoise.wrapS = THREE.RepeatWrapping;
    blueNoise.wrapT = THREE.RepeatWrapping;
    blueNoise.minFilter = THREE.NearestFilter;
    blueNoise.magFilter = THREE.NearestFilter;

    const material = new THREE.ShaderMaterial({
      uniforms: {
        resolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
        time: { value: 0.0 },
        frame: { value: 0 },
        blueNoise: { value: blueNoise },
        detailTex: { value: null },

        cameraOrigin: { value: new THREE.Vector3() },
        cameraTarget: { value: ORBIT_INITIAL.target.clone() },

        sunDirection: { value: SUN_INITIAL.clone().normalize() },
        sunIntensity: { value: 1.0 },

        windDirection: { value: new THREE.Vector2(1.0, 0.0) },
        windStrength: { value: 0.55 },
        windSpeed: { value: 1.0 },
        foamAmount: { value: 0.5 },

        waveAmplitude: { value: 1.0 },
        waveChoppiness: { value: 0.5 },
        waveScale: { value: 1.0 },

        debugMode: this.debugUniforms_.debugMode,
      },
      vertexShader: vertexShader,
      fragmentShader: await loadFragmentShader('fragment-shader.glsl'),
    });

    const oceanDetailGenerator = createOceanDetailGenerator(this.threejs_);
    await oceanDetailGenerator.init_();
    oceanDetailGenerator.onLoad = () => {
      const atlas = oceanDetailGenerator.Info['diffuse'].atlas;
      material.uniforms.detailTex.value = atlas;
      compositeMaterial.uniforms.detailTex.value = atlas;
    };
    oceanDetailGenerator.Load();

    const geometry = new THREE.PlaneGeometry(1, 1);
    const plane = new THREE.Mesh(geometry, material);
    plane.position.set(0.5, 0.5, 0);
    this.scene_.add(plane);

    this.material_ = material;

    this.updateSunDirection_();
    this.updateWindDirection_();

    this.clock_ = new THREE.Clock();
    this.totalTime_ = 0;
    this.onWindowResize_();
    this.raf_();
  }

  setupInput_() {
    const domElement = this.threejs_.domElement;
    let dragging = false;
    let lastX = 0;
    let lastY = 0;

    domElement.addEventListener('pointerdown', (e) => {
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
    }, false);

    window.addEventListener('pointermove', (e) => {
      if (!dragging) {
        return;
      }
      const dx = e.clientX - lastX;
      const dy = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;

      this.orbitDesired_.yaw -= dx * 0.005;
      this.orbitDesired_.pitch += dy * 0.005;
      this.orbitDesired_.pitch = Math.max(PITCH_MIN, Math.min(PITCH_MAX, this.orbitDesired_.pitch));
    }, false);

    window.addEventListener('pointerup', () => {
      dragging = false;
    }, false);

    domElement.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.orbitDesired_.radius *= Math.exp(e.deltaY * 0.001);
      this.orbitDesired_.radius = Math.max(RADIUS_MIN, Math.min(RADIUS_MAX, this.orbitDesired_.radius));
    }, { passive: false });
  }

  setupGui_() {
    const gui = new GUI({ title: 'Waves v1' });
    const u = this.material_.uniforms;

    const waves = gui.addFolder('Olas');
    waves.add(u.waveAmplitude, 'value', 0.2, 2.5, 0.01).name('amplitud');
    waves.add(u.waveChoppiness, 'value', 0, 1, 0.01).name('choppiness');
    waves.add(u.waveScale, 'value', 0.4, 2.2, 0.01).name('escala');
    waves.close();

    const wind = gui.addFolder('Viento');
    wind.add(this.windParams_, 'azimuth', -180, 180, 1)
        .name('azimut').onChange(() => this.updateWindDirection_());
    wind.add(this.windParams_, 'strength', 0, 1.2, 0.01).name('fuerza');
    wind.add(this.windParams_, 'speed', 0, 3, 0.01).name('velocidad');
    wind.add(u.foamAmount, 'value', 0, 1, 0.01).name('espuma');
    wind.close();

    const light = gui.addFolder('Iluminación');
    light.add(this.sunParams_, 'azimuth', -180, 180, 1)
        .name('sol azimut').onChange(() => this.updateSunDirection_());
    light.add(this.sunParams_, 'elevation', 3, 80, 1)
        .name('sol elevación').onChange(() => this.updateSunDirection_());
    light.add(this.sunParams_, 'intensity', 0, 2.5, 0.01)
        .name('intensidad').onChange((v) => {
          u.sunIntensity.value = v;
        });
    light.close();

    const animation = gui.addFolder('Animación');
    animation.add(this.animParams_, 'timeSpeed', 0, 3, 0.01).name('velocidad del tiempo');
    animation.close();

    const debug = gui.addFolder('Debug');
    debug.add(this.debugUniforms_.debugMode, 'value',
        { Off: 0, 'Textura detalle': 1, 'Máscara espuma': 2, Normales: 3 })
        .name('vista');
    debug.close();

    // Start minimized; the user expands it on demand.
    gui.close();
  }

  updateSunDirection_() {
    const azimuth = this.sunParams_.azimuth * Math.PI / 180.0;
    const elevation = this.sunParams_.elevation * Math.PI / 180.0;
    this.material_.uniforms.sunDirection.value.set(
        Math.cos(elevation) * Math.sin(azimuth),
        Math.sin(elevation),
        Math.cos(elevation) * Math.cos(azimuth));
    this.material_.uniforms.sunIntensity.value = this.sunParams_.intensity;
  }

  updateWindDirection_() {
    const azimuth = this.windParams_.azimuth * Math.PI / 180.0;
    this.material_.uniforms.windDirection.value.set(Math.cos(azimuth), Math.sin(azimuth));
  }

  updateOrbit_(dt) {
    // Damped follow of the desired orbit parameters.
    const t = Math.min(1.0, dt * 10.0);
    const cur = this.orbitCurrent_;
    const des = this.orbitDesired_;
    cur.radius += (des.radius - cur.radius) * t;
    cur.yaw += (des.yaw - cur.yaw) * t;
    cur.pitch += (des.pitch - cur.pitch) * t;

    const cosPitch = Math.cos(cur.pitch);
    this.material_.uniforms.cameraOrigin.value.set(
        cur.target.x + cur.radius * cosPitch * Math.sin(cur.yaw),
        cur.target.y + cur.radius * Math.sin(cur.pitch),
        cur.target.z + cur.radius * cosPitch * Math.cos(cur.yaw));
  }

  onWindowResize_() {
    this.threejs_.setSize(window.innerWidth, window.innerHeight);
    this.rt_.setSize(window.innerWidth * this.rtScale_, window.innerHeight * this.rtScale_);

    if (!this.material_) {
      return;
    }
    this.material_.uniforms.resolution.value = new THREE.Vector2(this.rt_.width, this.rt_.height);
    this.compositeMaterial_.uniforms.resolution.value =
        new THREE.Vector2(window.innerWidth, window.innerHeight);
    this.compositeMaterial_.uniforms.frameResolution.value =
        new THREE.Vector2(this.rt_.width, this.rt_.height);
  }

  raf_() {
    requestAnimationFrame(() => {
      this.step_(this.clock_.getDelta());
      this.render_();
      this.raf_();
    });
  }

  step_(timeElapsed) {
    this.totalTime_ += timeElapsed * this.animParams_.timeSpeed;

    this.updateOrbit_(timeElapsed);

    this.material_.uniforms.time.value = this.totalTime_;
    this.material_.uniforms.frame.value = this.material_.uniforms.frame.value + 1;
  }

  render_() {
    this.threejs_.setRenderTarget(this.rt_);
    this.threejs_.render(this.scene_, this.camera_);

    this.threejs_.setRenderTarget(null);
    this.compositeMaterial_.uniforms.frameTexture.value = this.rt_.texture;
    this.threejs_.render(this.finalScene_, this.camera_);
  }
}

export { App };
