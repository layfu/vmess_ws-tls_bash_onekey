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
  const MAX_ANIMATED_EDGES = 30;

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
  let hovered = null;

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

  function fmtCount(n) {
    return n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n);
  }

  function keyOf(link) {
    return link.source + '\u0000' + link.target + '\u0000' + (link.status || '');
  }

  function computeStructureKey(nodes, links) {
    return nodes.map((n) => n.id).sort().join('|') + '::' +
      links.map(keyOf).sort().join('|');
  }

  function edgeWidth(count, maxCount) {
    return 1 + Math.min(1, count / Math.max(maxCount, 1)) * 5;
  }

  function layout() {
    const byLayer = Array.from({ length: LAYERS }, () => []);
    for (const n of data.nodes) byLayer[layerOf(n.kind)].push(n);
    let maxH = 0;
    for (const arr of byLayer) {
      arr.sort((a, b) => (b.count - a.count) || a.id.localeCompare(b.id));
      maxH = Math.max(maxH, arr.length * NODE_PITCH);
    }
    const stageW = PAD_X * 2 + LAYERS * COL_W;
    const stageH = PAD_Y * 2 + Math.max(maxH, NODE_PITCH);
    stage.style.width = stageW + 'px';
    stage.style.height = stageH + 'px';
    svg.setAttribute('viewBox', '0 0 ' + stageW + ' ' + stageH);

    nodeCenter = new Map();
    for (let li = 0; li < LAYERS; li++) {
      const arr = byLayer[li];
      const layerH = arr.length * NODE_PITCH;
      const yStart = PAD_Y + (maxH - layerH) / 2;
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
      el.className = 'topo-node kind-' + n.kind;
      el.dataset.id = n.id;
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
      count.textContent = fmtCount(n.count);
      el.appendChild(dot);
      el.appendChild(label);
      el.appendChild(count);

      el.addEventListener('mouseenter', () => highlight(n.id, n.kind === 'user'));
      el.addEventListener('mouseleave', clearHighlight);
      nodesEl.appendChild(el);
      nodeEls.set(n.id, el);
    }
  }

  function buildEdges() {
    const maxCount = data.links.reduce((m, l) => Math.max(m, l.count), 1);
    const animated = new Set(
      data.links.slice().sort((a, b) => b.count - a.count)
        .slice(0, MAX_ANIMATED_EDGES).map(keyOf)
    );
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
      const width = edgeWidth(l.count, maxCount);

      const g = document.createElementNS(SVG_NS, 'g');
      g.setAttribute('class', 'topo-edge');
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

      if (!reducedMotion && animated.has(keyOf(l))) {
        for (let i = 0; i < 2; i++) {
          const dot = document.createElementNS(SVG_NS, 'circle');
          dot.setAttribute('class', 'topo-edge-dot');
          dot.setAttribute('r', String(2.4 - i * 0.7));
          dot.setAttribute('fill', color);
          const anim = document.createElementNS(SVG_NS, 'animateMotion');
          anim.setAttribute('dur', '2.4s');
          anim.setAttribute('repeatCount', 'indefinite');
          anim.setAttribute('begin', (i * 1.2) + 's');
          anim.setAttribute('path', d);
          dot.appendChild(anim);
          g.appendChild(dot);
        }
      }
      svg.appendChild(g);
      edgeEls.set(keyOf(l), { g, track });
      edgeList[i] = { g, track };
    }
  }

  function updateInPlace() {
    for (const n of data.nodes) {
      const el = nodeEls.get(n.id);
      if (!el) continue;
      const c = el.querySelector('.topo-node-count');
      if (c) c.textContent = fmtCount(n.count);
    }
    const maxCount = data.links.reduce((m, l) => Math.max(m, l.count), 1);
    for (const l of data.links) {
      const e = edgeEls.get(keyOf(l));
      if (e) e.track.setAttribute('stroke-width', String(edgeWidth(l.count, maxCount) + 6));
    }
  }

  function highlight(id, isUser) {
    if (hovered === id) return;
    hovered = id;
    const activeNodes = new Set([id]);
    const activeEdges = new Set();
    const path = isUser ? userPaths[id] : null;
    if (path && path.length) {
      for (const li of path) {
        activeEdges.add(li);
        const l = data.links[li];
        if (l) {
          activeNodes.add(l.source);
          activeNodes.add(l.target);
        }
      }
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
  }

  function clearHighlight() {
    hovered = null;
    for (const el of nodeEls.values()) el.classList.remove('dim');
    for (const e of edgeEls.values()) e.g.classList.remove('dim');
  }

  function renderSummary() {
    const totals = data.totals || {};
    const parts = Object.keys(totals).map((k) => statusLabel(k) + ' ' + totals[k] + ' 次');
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
    }
    renderSummary();
  }

  window.PanelTopology = {
    update(next) {
      data = next || { nodes: [], links: [], totals: {}, user_paths: {} };
      render();
    },
  };

  window.dispatchEvent(new CustomEvent('panel-topology-ready'));
})();
