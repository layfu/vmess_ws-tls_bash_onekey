// 路由拓扑：用户 → 协议 → 服务器 → 出口 → 目标。
// 原生 HTML 节点 + SVG 边，零依赖。
(function () {
  'use strict';

  const SVG_NS = 'http://www.w3.org/2000/svg';
  const PAD_X = 18;
  const PAD_Y = 14;
  const COL_W = 186;
  const NODE_W = 150;
  const NODE_H = 38;
  const NODE_PITCH = 46;
  const LAYERS = 5;
  const MIN_STAGE_H = 200;
  const PARTICLE_COUNT = 2;
  const FLOW_DURATION = 3;
  const ANIM_MIN_BYTES = 1024;
  const ANIM_RATIO = 0.05;

  const STATUS_COLORS = {
    direct: 'rgb(62, 207, 155)',
    warp: 'rgb(255, 180, 84)',
    blocked: 'rgb(255, 90, 90)',
    unknown: 'rgb(107, 118, 134)',
  };
  const KIND_COLORS = {
    user: 'rgb(91, 140, 255)',
    protocol: 'rgb(167, 139, 250)',
    server: 'rgb(91, 140, 255)',
    target: 'rgb(139, 155, 180)',
  };
  const NEUTRAL_EDGE = 'rgb(129, 140, 248)';

  const stage = document.getElementById('topo-stage');
  const svg = document.getElementById('topo-edges');
  const nodesEl = document.getElementById('topo-nodes');
  const emptyEl = document.getElementById('topo-empty');
  const summaryEl = document.getElementById('topo-summary');

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let data = { nodes: [], links: [], totals: {}, user_paths: {} };
  let structureKey = '';
  let nodeEls = new Map();
  let edgeEls = new Map();
  let edgeList = [];
  let nodeCenter = new Map();
  let adjacency = new Map();
  let userPaths = {};
  let userHover = null;
  let hovered = null;
  let hiddenByTab = document.hidden;
  let offscreen = false;
  let animationsPaused = false;

  // 页面不可见或卡片滚出视口时暂停 SMIL 粒子，省 CPU。
  function applyPause() {
    const paused = hiddenByTab || offscreen;
    if (paused === animationsPaused) return;
    animationsPaused = paused;
    if (typeof svg.pauseAnimations !== 'function') return;
    if (paused) svg.pauseAnimations();
    else svg.unpauseAnimations();
  }

  function layerOf(kind) {
    if (kind === 'user') return 0;
    if (kind === 'protocol') return 1;
    if (kind === 'server') return 2;
    if (kind === 'target') return 4;
    return 3;
  }

  function nodeColor(kind) {
    return KIND_COLORS[kind] || STATUS_COLORS[kind] || KIND_COLORS.target;
  }

  function edgeColor(status) {
    return (status && STATUS_COLORS[status]) || NEUTRAL_EDGE;
  }

  function statusLabel(s) {
    return { direct: '直连', warp: 'WARP', blocked: '封禁', unknown: '未知' }[s] || s;
  }

  const byteFmt = new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 1 });
  function fmtBytes(n) {
    if (!n) return '0 B';
    if (n < 1024) return n + ' B';
    const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
    let i = -1;
    do { n /= 1024; i++; } while (n >= 1024 && i < units.length - 1);
    return byteFmt.format(n) + ' ' + units[i];
  }

  // 数值按单位格式化：字节或次数。
  function fmtValue(v, unit) {
    return unit === 'count' ? v + ' 次' : fmtBytes(v);
  }

  function keyOf(link) {
    return link.source + '\u0000' + link.target + '\u0000' + (link.status || '');
  }

  function computeStructureKey(nodes, links) {
    return nodes.map((n) => n.id).sort().join('|') + '::' +
      links.map(keyOf).sort().join('|');
  }

  function unitMax(links, unit) {
    let m = 1;
    for (const l of links) {
      if ((l.unit || 'bytes') === unit && l.value > m) m = l.value;
    }
    return m;
  }

  function edgeWidth(link, maxBytes, maxCount) {
    const max = link.unit === 'count' ? maxCount : maxBytes;
    return 1 + Math.min(1, link.value / Math.max(max, 1)) * 5;
  }

  // 相对门槛：只看这条边占同类最大值的比例，突出主干线路。
  function shouldAnimate(link, maxBytes, maxCount) {
    const isCount = link.unit === 'count';
    const max = isCount ? maxCount : maxBytes;
    const min = isCount ? 2 : ANIM_MIN_BYTES;
    return link.value >= Math.max(min, max * ANIM_RATIO);
  }

  function layout() {
    const byLayer = Array.from({ length: LAYERS }, () => []);
    for (const n of data.nodes) byLayer[layerOf(n.kind)].push(n);
    let maxH = 0;
    for (const arr of byLayer) {
      arr.sort((a, b) => (b.value - a.value) || a.id.localeCompare(b.id));
      maxH = Math.max(maxH, arr.length * NODE_PITCH);
    }
    const stageW = PAD_X * 2 + LAYERS * COL_W;
    // 画布高度与 CSS min-height 对齐，并把整图垂直居中，避免 SVG viewBox 与
    // 实际高度不一致时 preserveAspectRatio 造成连线相对节点偏移。
    const contentH = PAD_Y * 2 + Math.max(maxH, NODE_PITCH);
    const stageH = Math.max(contentH, MIN_STAGE_H);
    const yOffset = (stageH - contentH) / 2;
    stage.style.width = stageW + 'px';
    stage.style.height = stageH + 'px';
    svg.setAttribute('viewBox', '0 0 ' + stageW + ' ' + stageH);

    nodeCenter = new Map();
    for (let li = 0; li < LAYERS; li++) {
      const arr = byLayer[li];
      const layerH = arr.length * NODE_PITCH;
      const yStart = yOffset + PAD_Y + (maxH - layerH) / 2;
      const cx = PAD_X + li * COL_W + COL_W / 2;
      arr.forEach((n, i) => {
        nodeCenter.set(n.id, { x: cx, y: yStart + i * NODE_PITCH + NODE_H / 2 });
      });
    }
  }

  function clearStage() {
    nodesEl.textContent = '';
    svg.textContent = '';
    nodeEls = new Map();
    edgeEls = new Map();
    edgeList = [];
    adjacency = new Map();
    userHover = null;
    hovered = null;
  }

  function buildAdjacency() {
    adjacency = new Map();
    for (const n of data.nodes) adjacency.set(n.id, new Set());
    for (const l of data.links) {
      const a = adjacency.get(l.source);
      const b = adjacency.get(l.target);
      if (a && b) {
        a.add(l.target);
        b.add(l.source);
      }
    }
  }

  function buildNodes() {
    for (const n of data.nodes) {
      const c = nodeCenter.get(n.id);
      if (!c) continue;
      const el = document.createElement('div');
      el.className = 'topo-node kind-' + n.kind + (n.unit === 'count' ? ' unit-count' : '');
      el.dataset.id = n.id;
      el.dataset.unit = n.unit;
      el.style.left = (c.x - NODE_W / 2) + 'px';
      el.style.top = (c.y - NODE_H / 2) + 'px';
      el.style.width = NODE_W + 'px';
      el.style.height = NODE_H + 'px';
      el.title = n.label;

      const dot = document.createElement('i');
      dot.className = 'topo-dot';
      dot.style.background = nodeColor(n.kind);
      const label = document.createElement('span');
      label.className = 'topo-node-label';
      label.textContent = n.label;
      const count = document.createElement('span');
      count.className = 'topo-node-count';
      count.textContent = fmtValue(n.value, n.unit);
      el.appendChild(dot);
      el.appendChild(label);
      el.appendChild(count);

      el.addEventListener('mouseenter', () => highlight(n.id, n.kind === 'user'));
      el.addEventListener('mouseleave', clearHighlight);
      nodesEl.appendChild(el);
      nodeEls.set(n.id, el);
    }
  }

  // 沿边添加流动粒子：负 begin 错峰，opacity 淡入淡出遮住循环回到起点的跳变。
  function addParticles(g, d, color) {
    const dots = [];
    for (let p = 0; p < PARTICLE_COUNT; p++) {
      const begin = (-p * FLOW_DURATION / PARTICLE_COUNT) + 's';
      const dot = document.createElementNS(SVG_NS, 'circle');
      dot.setAttribute('class', 'topo-edge-dot');
      dot.setAttribute('r', '2.1');
      dot.setAttribute('fill', color);
      const motion = document.createElementNS(SVG_NS, 'animateMotion');
      motion.setAttribute('dur', FLOW_DURATION + 's');
      motion.setAttribute('repeatCount', 'indefinite');
      motion.setAttribute('begin', begin);
      motion.setAttribute('path', d);
      const fade = document.createElementNS(SVG_NS, 'animate');
      fade.setAttribute('attributeName', 'opacity');
      fade.setAttribute('values', '0;1;1;0');
      fade.setAttribute('keyTimes', '0;0.12;0.88;1');
      fade.setAttribute('dur', FLOW_DURATION + 's');
      fade.setAttribute('repeatCount', 'indefinite');
      fade.setAttribute('begin', begin);
      dot.appendChild(motion);
      dot.appendChild(fade);
      g.appendChild(dot);
      dots.push(dot);
    }
    return dots;
  }

  function removeParticles(entry) {
    if (!entry.dots) return;
    for (const dot of entry.dots) dot.remove();
    entry.dots = null;
  }

  function buildEdges() {
    const maxBytes = unitMax(data.links, 'bytes');
    const maxCount = unitMax(data.links, 'count');
    for (let i = 0; i < data.links.length; i++) {
      const l = data.links[i];
      const s = nodeCenter.get(l.source);
      const t = nodeCenter.get(l.target);
      if (!s || !t) {
        edgeList[i] = null;
        continue;
      }
      const sx = s.x + NODE_W / 2;
      const tx = t.x - NODE_W / 2;
      const mx = (sx + tx) / 2;
      const d = 'M' + sx + ' ' + s.y + ' C' + mx + ' ' + s.y + ', ' + mx + ' ' + t.y + ', ' + tx + ' ' + t.y;
      const color = edgeColor(l.status);
      const width = edgeWidth(l, maxBytes, maxCount);

      const g = document.createElementNS(SVG_NS, 'g');
      g.setAttribute('class', 'topo-edge' + (l.unit === 'count' ? ' unit-count' : ''));
      const track = document.createElementNS(SVG_NS, 'path');
      track.setAttribute('class', 'topo-edge-track');
      track.setAttribute('d', d);
      track.setAttribute('stroke', color);
      track.setAttribute('stroke-width', String(width + 6));
      const line = document.createElementNS(SVG_NS, 'path');
      line.setAttribute('class', 'topo-edge-line');
      line.setAttribute('d', d);
      line.setAttribute('stroke', color);
      g.appendChild(track);
      g.appendChild(line);

      const entry = { g, track, d, color, dots: null };
      if (!reducedMotion && shouldAnimate(l, maxBytes, maxCount)) {
        entry.dots = addParticles(g, d, color);
      }
      svg.appendChild(g);
      edgeEls.set(keyOf(l), entry);
      edgeList[i] = entry;
    }
  }

  function updateInPlace() {
    for (const n of data.nodes) {
      const el = nodeEls.get(n.id);
      if (!el) continue;
      const c = el.querySelector('.topo-node-count');
      if (c) c.textContent = fmtValue(n.value, n.unit);
    }
    const maxBytes = unitMax(data.links, 'bytes');
    const maxCount = unitMax(data.links, 'count');
    for (let i = 0; i < data.links.length; i++) {
      const l = data.links[i];
      const entry = edgeList[i];
      if (!entry) continue;
      entry.track.setAttribute('stroke-width', String(edgeWidth(l, maxBytes, maxCount) + 6));
      // 数据刷新时同步粒子的增删，保证动画状态与当前数值/门槛一致。
      if (!reducedMotion) {
        const want = shouldAnimate(l, maxBytes, maxCount);
        if (want && !entry.dots) {
          entry.dots = addParticles(entry.g, entry.d, entry.color);
        } else if (!want && entry.dots) {
          removeParticles(entry);
        }
      }
    }
  }

  // 悬停用户时，把该用户路径上的节点数值与连线粗细换成"该用户自己"的流量，
  // 让每条链路的数值都对应这个人，而不是全体合计。
  function applyUserValues() {
    if (!userHover) return;
    let maxBytes = 1;
    let maxCount = 1;
    for (const [i, v] of userHover.links) {
      const l = data.links[i];
      if (!l) continue;
      if ((l.unit || 'bytes') === 'count') {
        if (v > maxCount) maxCount = v;
      } else if (v > maxBytes) {
        maxBytes = v;
      }
    }
    for (const [i, v] of userHover.links) {
      const l = data.links[i];
      const e = edgeList[i];
      if (!l || !e) continue;
      const max = (l.unit || 'bytes') === 'count' ? maxCount : maxBytes;
      e.track.setAttribute('stroke-width', String(1 + Math.min(1, v / Math.max(max, 1)) * 5 + 6));
    }
    for (const [nid, v] of userHover.nodes) {
      const el = nodeEls.get(nid);
      if (!el) continue;
      const c = el.querySelector('.topo-node-count');
      if (c) c.textContent = fmtValue(v, el.dataset.unit);
    }
  }

  function clearUserValues() {
    userHover = null;
    const maxBytes = unitMax(data.links, 'bytes');
    const maxCount = unitMax(data.links, 'count');
    for (const n of data.nodes) {
      const el = nodeEls.get(n.id);
      if (!el) continue;
      const c = el.querySelector('.topo-node-count');
      if (c) c.textContent = fmtValue(n.value, n.unit);
    }
    for (let i = 0; i < data.links.length; i++) {
      const e = edgeList[i];
      if (e) e.track.setAttribute('stroke-width', String(edgeWidth(data.links[i], maxBytes, maxCount) + 6));
    }
  }

  function highlight(id, isUser) {
    if (hovered === id) return;
    hovered = id;
    const activeNodes = new Set([id]);
    const activeEdges = new Set();
    const path = isUser ? userPaths[id] : null;
    let links = null;
    let nodes = null;
    if (path && path.links && path.links.length) {
      links = new Map();
      for (const pl of path.links) {
        activeEdges.add(pl.i);
        links.set(pl.i, pl.v);
        const l = data.links[pl.i];
        if (l) {
          activeNodes.add(l.source);
          activeNodes.add(l.target);
        }
      }
      nodes = new Map(Object.entries(path.nodes || {}));
    } else {
      const nbrs = adjacency.get(id) || new Set();
      for (const nb of nbrs) activeNodes.add(nb);
      for (let i = 0; i < data.links.length; i++) {
        const l = data.links[i];
        if (l.source === id || l.target === id) activeEdges.add(i);
      }
    }
    for (const [nid, el] of nodeEls) el.classList.toggle('dim', !activeNodes.has(nid));
    for (let i = 0; i < edgeList.length; i++) {
      const e = edgeList[i];
      if (e) e.g.classList.toggle('dim', !activeEdges.has(i));
    }
    if (links) {
      userHover = { links, nodes };
      applyUserValues();
    } else if (userHover) {
      clearUserValues();
    }
  }

  function clearHighlight() {
    hovered = null;
    for (const el of nodeEls.values()) el.classList.remove('dim');
    for (const e of edgeEls.values()) e.g.classList.remove('dim');
    if (userHover) clearUserValues();
  }

  function renderSummary() {
    const totals = data.totals || {};
    const parts = Object.keys(totals).map((k) => statusLabel(k) + ' ' + fmtValue(totals[k], k === 'blocked' ? 'count' : 'bytes'));
    summaryEl.textContent = parts.length ? '路由拓扑（近 24 小时）：' + parts.join('，') : '暂无连接数据';
  }

  function render() {
    const nodes = data.nodes || [];
    const links = data.links || [];
    userPaths = data.user_paths || {};
    if (!nodes.length) {
      clearStage();
      structureKey = '';
      stage.style.width = '';
      stage.style.height = '';
      emptyEl.hidden = false;
      renderSummary();
      applyPause();
      return;
    }
    emptyEl.hidden = true;
    const key = computeStructureKey(nodes, links);
    if (key !== structureKey) {
      structureKey = key;
      clearStage();
      layout();
      buildAdjacency();
      buildNodes();
      buildEdges();
    } else {
      updateInPlace();
      if (userHover) applyUserValues();
    }
    renderSummary();
    applyPause();
  }

  window.PanelTopology = {
    update(next) {
      data = next || { nodes: [], links: [], totals: {}, user_paths: {} };
      render();
    },
  };

  document.addEventListener('visibilitychange', () => {
    hiddenByTab = document.hidden;
    applyPause();
  });
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) offscreen = !entry.isIntersecting;
      applyPause();
    }, { threshold: 0 });
    io.observe(stage.closest('.topo-card') || stage);
  }

  window.dispatchEvent(new CustomEvent('panel-topology-ready'));
})();
