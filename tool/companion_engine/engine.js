// ASKODOX companion engine: renders ONE VRM avatar (three.js + @pixiv/three-vrm)
// inside a transparent WebView. Driven entirely from Flutter:
//   AskodoxEngine.load(url)        -> loads a .vrm (VRM 0.x or 1.0)
//   AskodoxEngine.setMood(name)    -> idle|greeting|listening|thinking|speaking|explaining|success|help
//   AskodoxEngine.setMouth(a, v)   -> lip-sync: viseme (aa|ih|ou|ee|oh) + weight 0..1
//   AskodoxEngine.setMic(level)    -> 0..1, listening lean-in
//   AskodoxEngine.pause()/resume() -> lifecycle (no frames while paused)
// Reports to Flutter through the `AskodoxEngineStats` JS channel.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';

const post = (o) => { try { AskodoxEngineStats.postMessage(JSON.stringify(o)); } catch (_) {} };

const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, powerPreference: 'low-power' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(24, 1, 0.1, 20);
scene.add(new THREE.AmbientLight(0xffffff, 1.2));
const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(-0.6, 1.2, 1.5);
scene.add(key);

let vrm = null, mood = 'idle', mic = 0, paused = false, t0 = performance.now();
let viseme = 'aa', visemeWeight = 0, blinkAt = 1.5, blinkT = -1, gazeX = 0, gazeY = 0, gazeAt = 3;
const visemes = ['aa', 'ih', 'ou', 'ee', 'oh'];

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / Math.max(h, 1);
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

function frameUpperBody() {
  // Head + shoulders + hands framing from the humanoid bones.
  const head = vrm.humanoid.getNormalizedBoneNode('head');
  const pos = new THREE.Vector3();
  head.getWorldPosition(pos);
  camera.position.set(0, pos.y - 0.12, 1.55);
  camera.lookAt(0, pos.y - 0.22, 0);
}

async function load(url) {
  const started = performance.now();
  try {
    const loader = new GLTFLoader();
    loader.register((parser) => new VRMLoaderPlugin(parser));
    const gltf = await loader.loadAsync(url);
    const v = gltf.userData.vrm;
    VRMUtils.removeUnnecessaryVertices(gltf.scene);
    VRMUtils.combineSkeletons(gltf.scene);
    VRMUtils.rotateVRM0(v);
    v.scene.traverse((o) => { o.frustumCulled = false; });
    if (vrm) { scene.remove(vrm.scene); VRMUtils.deepDispose(vrm.scene); }
    vrm = v;
    scene.add(vrm.scene);
    frameUpperBody();
    let tris = 0;
    vrm.scene.traverse((o) => { if (o.isMesh && o.geometry.index) tris += o.geometry.index.count / 3; });
    post({ event: 'loaded', ms: Math.round(performance.now() - started), triangles: Math.round(tris),
      name: (vrm.meta && (vrm.meta.name || vrm.meta.title)) || '' });
  } catch (e) {
    post({ event: 'error', message: String(e && e.message || e) });
  }
}

function setExpr(name, w) { if (vrm && vrm.expressionManager) vrm.expressionManager.setValue(name, w); }
function bone(name) { return vrm.humanoid.getNormalizedBoneNode(name); }

// Mood -> body pose (normalized humanoid bones, radians) + face.
function pose(time) {
  const s = Math.sin(time * 2 * Math.PI / 2.4);
  const head = bone('head'), neck = bone('neck'), spine = bone('spine');
  const lUp = bone('leftUpperArm'), rUp = bone('rightUpperArm'), lLow = bone('leftLowerArm'), rLow = bone('rightLowerArm');
  // Relaxed arms down by default.
  lUp.rotation.set(0, 0, 1.2); rUp.rotation.set(0, 0, -1.2);
  lLow.rotation.set(0, 0, 0.1); rLow.rotation.set(0, 0, -0.1);
  head.rotation.set(0, 0, 0); neck.rotation.set(0, 0, 0);
  spine.rotation.set(0.02 * Math.sin(time * 1.3), 0, 0); // breathing
  let happy = 0, sad = 0, surprised = 0;
  switch (mood) {
    case 'greeting':
      rUp.rotation.set(0, 0, 0.3); rLow.rotation.set(0, 0, -1.4 + 0.25 * Math.sin(time * 9)); happy = 0.8;
      head.rotation.z = 0.08; break;
    case 'listening':
      head.rotation.z = 0.14 + 0.06 * mic; spine.rotation.x += 0.05 * mic; surprised = 0.1 + 0.2 * mic; break;
    case 'thinking':
      head.rotation.set(-0.12, 0.25 * s, -0.05);
      rUp.rotation.set(0.3, 0, -0.6); rLow.rotation.set(0, -2.2, 0); break;
    case 'speaking':
      head.rotation.set(0.03 * Math.sin(time * 5), 0.08 * s, 0);
      lLow.rotation.set(0, 0.4 + 0.2 * Math.max(0, s), 0.1); rLow.rotation.set(0, -0.4 - 0.2 * Math.max(0, -s), -0.1);
      happy = 0.2; break;
    case 'explaining':
      head.rotation.y = -0.3; rUp.rotation.set(0, -0.4, -0.3); rLow.rotation.set(0, -0.2, 0); happy = 0.3; break;
    case 'success':
      happy = 1; lUp.rotation.set(0, 0, 0.2); rUp.rotation.set(0, 0, -0.2);
      lLow.rotation.set(0, 0, 1.2); rLow.rotation.set(0, 0, -1.2); break;
    case 'help':
      sad = 0.6; lUp.rotation.set(0, 0, 0.9); rUp.rotation.set(0, 0, -0.9);
      lLow.rotation.set(0, 0.9, 0.2); rLow.rotation.set(0, -0.9, -0.2); head.rotation.x = 0.08; break;
    default:
      happy = 0.15;
  }
  setExpr('happy', happy); setExpr('sad', sad); setExpr('surprised', surprised);
}

function face(time, dt) {
  // Natural blink every 2.5-6 s.
  if (blinkT < 0 && time > blinkAt) blinkT = 0;
  if (blinkT >= 0) {
    blinkT += dt;
    const w = blinkT < 0.07 ? blinkT / 0.07 : Math.max(0, 1 - (blinkT - 0.07) / 0.08);
    setExpr('blink', w);
    if (blinkT > 0.15) { blinkT = -1; blinkAt = time + 2.5 + Math.random() * 3.5; }
  }
  // Glances.
  if (time > gazeAt) { gazeX = (Math.random() - 0.5) * 0.6; gazeY = (Math.random() - 0.5) * 0.3; gazeAt = time + 2 + Math.random() * 4; }
  const eye = bone('leftEye'), eye2 = bone('rightEye');
  if (eye && eye2) { eye.rotation.set(gazeY * 0.2, gazeX * 0.3, 0); eye2.rotation.copy(eye.rotation); }
  // Lip-sync (driven by Flutter's existing voice hooks); demo cycle in the lab.
  for (const v of visemes) setExpr(v, v === viseme ? visemeWeight : 0);
}

let frames = 0, statAt = performance.now(), worst = 0, last = performance.now();
function tick() {
  if (paused) return;
  requestAnimationFrame(tick);
  const now = performance.now();
  const dt = Math.min(0.1, (now - last) / 1000);
  worst = Math.max(worst, now - last);
  last = now;
  const time = (now - t0) / 1000;
  if (vrm) { pose(time); face(time, dt); vrm.update(dt); }
  renderer.render(scene, camera);
  frames++;
  if (now - statAt > 2000) {
    const mem = performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null;
    post({ event: 'stats', fps: Math.round(frames * 1000 / (now - statAt)), worstFrameMs: Math.round(worst),
      drawCalls: renderer.info.render.calls, triangles: renderer.info.render.triangles, jsHeapMb: mem,
      gpuTextures: renderer.info.memory.textures });
    frames = 0; worst = 0; statAt = now;
  }
}
requestAnimationFrame(tick);

window.AskodoxEngine = {
  load,
  setMood: (m) => { mood = m; },
  setMouth: (v, w) => { viseme = visemes.includes(v) ? v : 'aa'; visemeWeight = Math.max(0, Math.min(1, w)); },
  setMic: (l) => { mic = Math.max(0, Math.min(1, l)); },
  pause: () => { paused = true; },
  resume: () => { if (paused) { paused = false; last = performance.now(); requestAnimationFrame(tick); } },
};
post({ event: 'ready', webgl2: renderer.capabilities.isWebGL2, maxTexture: renderer.capabilities.maxTextureSize });
