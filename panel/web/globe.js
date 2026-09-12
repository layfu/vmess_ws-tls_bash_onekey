// 实时路由地球：cobe 点阵地球 + SVG 流动虚线，展示客户端到服务器的线路走向。
import createGlobe from './vendor/cobe.esm.js';

const J = 0.8;
const ARC_CONTROL = 1.08;
const SAMPLES = 28;
const AUTO_ROTATE = 0.0035;
const EASE = 0.12;
const THETA0 = (23.44 * Math.PI) / 180;
const THETA_MAX = Math.PI / 2 - 0.08;
const MAX_LABELS = 5;

const COLORS = {
  direct: [0.243, 0.812, 0.608],
  warp: [1.0, 0.706, 0.329],
  blocked: [1.0, 0.353, 0.353],
  unknown: [0.42, 0.463, 0.525],
  server: [0.357, 0.549, 1.0],
};

const CSS_COLORS = {
  direct: 'rgb(62, 207, 155)',
  warp: 'rgb(255, 180, 84)',
  blocked: 'rgb(255, 90, 90)',
  unknown: 'rgb(107, 118, 134)',
  server: 'rgb(91, 140, 255)',
};

const stage = document.getElementById('globe-stage');
const canvas = document.getElementById('globe-canvas');
const trailsSvg = document.getElementById('globe-trails');
const labelsEl = document.getElementById('globe-labels');
const emptyEl = document.getElementById('globe-empty');
const summaryEl = document.getElementById('globe-summary');

let globe = null;
let width = 0;
let theta = THETA0;
let autoPhi = 0;
let dragPhi = 0;
let targetPhi = 0;
let targetTheta = THETA0;
let dragging = false;
let pointerX = 0;
let pointerY = 0;
let startPhi = 0;
let startTheta = THETA0;
let reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
let trailPaths = [];
let labelEls = [];
let pending = null;
let data = { server: null, nodes: [] };
let firstFrame = true;
let lastPhi = NaN;
let lastTheta = NaN;

function unit(lat, lng) {
  const t = (lat * Math.PI) / 180;
  const n = (lng * Math.PI) / 180 - Math.PI;
  const r = Math.cos(t);
  return [-r * Math.cos(n), Math.sin(t), r * Math.sin(n)];
}

function project(x, y, z, p, th) {
  const a = Math.cos(th);
  const o = Math.sin(th);
  const s = Math.cos(p);
  const c = Math.sin(p);
  return {
    x: (s * x + c * z + 1) / 2,
    y: (1 - (c * o * x + a * y - s * o * z)) / 2,
    z: -c * a * x + o * y + s * a * z,
  };
}

function projectLatLng(lat, lng, p, th) {
  const [x, y, z] = unit(lat, lng);
  return project(x * J, y * J, z * J, p, th);
}

function arcPath(from, to, p, th) {
  const a = unit(from[0], from[1]);
  const b = unit(to[0], to[1]);
  const sum = [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const len = Math.hypot(sum[0], sum[1], sum[2]);
  const control = len < 0.001 ? [0, ARC_CONTROL, 0] : sum.map((v) => (v / len) * ARC_CONTROL);
  let d = '';
  let pen = false;
  for (let k = 0; k <= SAMPLES; k += 1) {
    const t = k / SAMPLES;
    const o = 1 - t;
    const x = o * o * a[0] * J + 2 * o * t * control[0] + t * t * b[0] * J;
    const y = o * o * a[1] * J + 2 * o * t * control[1] + t * t * b[1] * J;
    const z = o * o * a[2] * J + 2 * o * t * control[2] + t * t * b[2] * J;
    const s = project(x, y, z, p, th);
    const dist = Math.hypot(s.x - 0.5, s.y - 0.5);
    if (!(s.z >= 0 || dist >= J / 2)) {
      pen = false;
      continue;
    }
    d += `${pen ? 'L' : 'M'}${(s.x * 100).toFixed(2)} ${(s.y * 100).toFixed(2)}`;
    pen = true;
  }
  return d;
}

function dominant(status) {
  let best = 'unknown';
  let bestCount = -1;
  for (const [key, value] of Object.entries(status || {})) {
    if (value > bestCount) {
      bestCount = value;
      best = key;
    }
  }
  return COLORS[best] ? best : 'unknown';
}

function markerSize(count) {
  return Math.min(0.05, 0.02 + Math.log2(count + 1) * 0.006);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function buildOverlay() {
  trailsSvg.textContent = '';
  labelsEl.textContent = '';
  trailPaths = [];
  labelEls = [];

  const server = data.server;
  const nodes = data.nodes || [];

  for (const node of nodes) {
    if (!server) continue;
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('stroke', CSS_COLORS[dominant(node.status)]);
    trailsSvg.appendChild(path);
    trailPaths.push({ path, from: [node.lat, node.lng], to: [server.lat, server.lng] });
  }

  const labeled = [];
  if (server) labeled.push({ lat: server.lat, lng: server.lng, name: server.name || '服务器', status: 'server', server: true });
  for (const node of nodes.slice(0, MAX_LABELS)) {
    labeled.push({ lat: node.lat, lng: node.lng, name: node.region || '未知', status: dominant(node.status) });
  }

  for (const item of labeled) {
    const el = document.createElement('span');
    el.className = 'globe-label' + (item.server ? ' server' : '');
    el.innerHTML = `<i style="--c:${CSS_COLORS[item.status] || CSS_COLORS.unknown}"></i>${escapeHtml(item.name)}`;
    labelsEl.appendChild(el);
    labelEls.push({ el, lat: item.lat, lng: item.lng });
  }

  renderSummary();
  emptyEl.hidden = nodes.length > 0;
}

function renderSummary() {
  const nodes = data.nodes || [];
  if (!nodes.length) {
    summaryEl.textContent = '暂无连接数据';
    return;
  }
  const parts = nodes.slice(0, 10).map((n) => `${n.region || '未知'} ${n.count} 次`);
  summaryEl.textContent = `客户端来源（近 24 小时）：${parts.join('，')}`;
}

function updateOverlay(p, th) {
  for (const trail of trailPaths) {
    trail.path.setAttribute('d', arcPath(trail.from, trail.to, p, th));
  }
  for (const label of labelEls) {
    const s = projectLatLng(label.lat, label.lng, p, th);
    label.el.style.transform = `translate(${(s.x * width).toFixed(1)}px, ${(s.y * width).toFixed(1)}px) translate(-50%, 10px)`;
    label.el.style.opacity = String(Math.min(1, Math.max(0, s.z / 0.12)));
  }
}

function applyData() {
  if (!globe) return;
  const server = data.server;
  const nodes = data.nodes || [];
  const markers = nodes.map((n) => ({
    location: [n.lat, n.lng],
    size: markerSize(n.count),
    color: COLORS[dominant(n.status)] || COLORS.unknown,
  }));
  if (server) {
    markers.push({ location: [server.lat, server.lng], size: 0.05, color: COLORS.server });
  }
  const arcs = [];
  if (server) {
    for (const n of nodes) {
      arcs.push({
        from: [n.lat, n.lng],
        to: [server.lat, server.lng],
        color: COLORS[dominant(n.status)] || COLORS.unknown,
      });
    }
  }
  globe.update({ markers, arcs });
  buildOverlay();
  updateOverlay(autoPhi + dragPhi, theta);
}

function onPointerDown(e) {
  dragging = true;
  pointerX = e.clientX;
  pointerY = e.clientY;
  startPhi = targetPhi;
  startTheta = targetTheta;
  canvas.setPointerCapture?.(e.pointerId);
}

function onPointerMove(e) {
  if (!dragging) return;
  const w = Math.max(width, 1);
  targetPhi = startPhi + ((e.clientX - pointerX) / w) * Math.PI * 2;
  targetTheta = Math.max(-THETA_MAX, Math.min(THETA_MAX, startTheta + ((e.clientY - pointerY) / w) * Math.PI));
}

function onPointerUp(e) {
  dragging = false;
  canvas.releasePointerCapture?.(e.pointerId);
}

function tick() {
  requestAnimationFrame(tick);
  if (!reduced && !dragging) autoPhi += AUTO_ROTATE;
  dragPhi += (targetPhi - dragPhi) * EASE;
  theta += (targetTheta - theta) * EASE;
  const p = autoPhi + dragPhi;
  if (!firstFrame && Math.abs(p - lastPhi) < 1e-5 && Math.abs(theta - lastTheta) < 1e-5) {
    return;
  }
  if (globe) {
    globe.update(firstFrame ? { phi: p, theta, width, height: width } : { phi: p, theta });
  }
  updateOverlay(p, theta);
  lastPhi = p;
  lastTheta = theta;
  firstFrame = false;
}

function measure() {
  const w = stage.offsetWidth;
  if (w > 0) width = w;
  return width;
}

function init() {
  measure();
  if (width === 0) {
    requestAnimationFrame(init);
    return;
  }
  try {
    globe = createGlobe(canvas, {
      devicePixelRatio: Math.min(window.devicePixelRatio || 1, 2),
      width,
      height: width,
      phi: 0,
      theta,
      dark: 1,
      diffuse: 0.4,
      mapSamples: 16000,
      mapBrightness: 4,
      baseColor: [0.18, 0.21, 0.25],
      markerColor: COLORS.server,
      glowColor: [0.357, 0.549, 1.0],
      markers: [],
      arcs: [],
      arcColor: COLORS.server,
      arcWidth: 0.4,
      arcHeight: 0.28,
      markerElevation: 0,
      opacity: 1,
    });
  } catch (err) {
    canvas.style.display = 'none';
    emptyEl.textContent = '当前浏览器不支持 WebGL';
    emptyEl.hidden = false;
    return;
  }
  canvas.addEventListener('pointerdown', onPointerDown);
  canvas.addEventListener('pointermove', onPointerMove);
  canvas.addEventListener('pointerup', onPointerUp);
  canvas.addEventListener('pointercancel', onPointerUp);
  window.addEventListener('resize', onResize);
  reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (pending) {
    data = pending;
    pending = null;
  }
  applyData();
  requestAnimationFrame(tick);
  window.dispatchEvent(new CustomEvent('panel-globe-ready'));
}

let resizeTimer = 0;
function onResize() {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    measure();
    if (globe && width > 0) {
      globe.update({ width, height: width });
      firstFrame = true;
      updateOverlay(autoPhi + dragPhi, theta);
    }
  }, 180);
}

window.PanelGlobe = {
  update(next) {
    data = next || { server: null, nodes: [] };
    if (globe) applyData();
    else pending = data;
  },
};

init();
