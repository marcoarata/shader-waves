const cache_ = new Map();

async function loadText(path) {
  if (!cache_.has(path)) {
    cache_.set(
        path,
        fetch(path).then((response) => {
          if (!response.ok) {
            throw new Error(`Failed to load shader: ${path} (${response.status})`);
          }
          return response.text();
        }));
  }
  return cache_.get(path);
}

// Loads a list of GLSL files and concatenates them in order.
export async function loadShaderProgram(paths) {
  const texts = await Promise.all(paths.map(loadText));
  return texts.join('\n');
}

// Shared include chain used by every fragment shader in the project.
const FRAGMENT_INCLUDES = [
  './shaders/header.glsl',
  './shaders/oklab.glsl',
  './shaders/common.glsl',
  './shaders/noise.glsl',
];

export function loadVertexShader() {
  return loadShaderProgram(['./shaders/vertex-shader.glsl']);
}

export function loadFragmentShader(name) {
  return loadShaderProgram([...FRAGMENT_INCLUDES, `./shaders/${name}`]);
}
