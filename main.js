import { App } from './js/app.js';

let APP_ = null;

window.addEventListener('DOMContentLoaded', async () => {
  APP_ = new App();
  await APP_.initialize();
});
