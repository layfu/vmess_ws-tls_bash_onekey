// ---- 格式化 ----
const byteFmt = (digits) => new Intl.NumberFormat('zh-CN', { maximumFractionDigits: digits });

function fmtBytes(n) {
  if (n == null) return '—';
  if (n < 1024) return n + ' B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < units.length - 1);
  const digits = n >= 100 ? 0 : (n >= 10 ? 1 : 2);
  return byteFmt(digits).format(n) + ' ' + units[i];
}

const fmtDateTime = new Intl.DateTimeFormat('zh-CN', {
  year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
});
const fmtHourAxis = new Intl.DateTimeFormat('zh-CN', {
  month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
});
const fmtDayAxis = new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit' });
const fmtClockAxis = new Intl.DateTimeFormat('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });

function fmtTime(ts) {
  if (!ts) return '—';
  return fmtDateTime.format(new Date(ts * 1000));
}

function fmtHourLabel(hour) { return fmtHourAxis.format(new Date(hour * 1000)); }
function fmtDayLabel(hour) { return fmtDayAxis.format(new Date(hour * 1000)); }
function fmtClockLabel(hour) { return fmtClockAxis.format(new Date(hour * 1000)); }

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

async function fetchJSON(url) {
  const res = await fetch(url, { cache: 'no-store' });
  if (res.status === 401) {
    window.location.replace('login');
    throw new Error('unauthorized');
  }
  if (!res.ok) throw new Error(res.statusText);
  return res.json();
}

function protoBadge(p) {
  const label = p === 'vmess' ? 'VMess' : (p === 'anytls' ? 'AnyTLS' : p);
  return `<span class="badge ${escapeHtml(p)}">${label}</span>`;
}

function statusBadge(s) {
  if (!s) return '<span class="badge">—</span>';
  const map = {
    direct: { cls: 'ok', label: '直连' },
    warp: { cls: 'warp', label: 'WARP' },
    blocked: { cls: 'blocked', label: '封禁' },
    rejected: { cls: 'blocked', label: '拒绝' },
  };
  const m = map[s] || { cls: '', label: escapeHtml(s) };
  return `<span class="badge ${m.cls}">${m.label}</span>`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

// ---- 表格排序 ----
const NUMERIC_SORT_KEYS = { uplink: 1, downlink: 1, total: 1, lifetime: 1, last_seen: 1 };

let overviewSort = { key: 'total', dir: 'desc' };
let histSort = { key: 'total', dir: 'desc' };

function overviewSortVal(u, key) {
  switch (key) {
    case 'protocol': return u.protocol || '';
    case 'username': return u.username || '';
    case 'uplink': return u.uplink || 0;
    case 'downlink': return u.downlink || 0;
    case 'total': return u.total || 0;
    case 'lifetime': return u.lifetime_total || 0;
    case 'online': return u.online ? 1 : 0;
    case 'last_seen': return u.last_seen || 0;
    default: return 0;
  }
}

function histSortVal(u, key) {
  switch (key) {
    case 'protocol': return u.protocol || '';
    case 'username': return u.username || '';
    case 'uplink': return u.uplink || 0;
    case 'downlink': return u.downlink || 0;
    case 'total': return (u.uplink || 0) + (u.downlink || 0);
    default: return 0;
  }
}

function sortRows(rows, getVal, sortState) {
  const dirMult = sortState.dir === 'asc' ? 1 : -1;
  return rows.slice().sort((a, b) => {
    const va = getVal(a, sortState.key);
    const vb = getVal(b, sortState.key);
    let c;
    if (typeof va === 'string' || typeof vb === 'string') {
      c = String(va).localeCompare(String(vb), 'zh-CN');
    } else {
      c = va === vb ? 0 : (va > vb ? 1 : -1);
    }
    return c * dirMult;
  });
}

function toggleSort(key, sortState) {
  if (sortState.key === key) {
    sortState.dir = sortState.dir === 'asc' ? 'desc' : 'asc';
  } else {
    sortState.key = key;
    sortState.dir = NUMERIC_SORT_KEYS[key] ? 'desc' : 'asc';
  }
}

function updateSortIndicators(tableId, sortState) {
  document.querySelectorAll('#' + tableId + ' th.sortable').forEach((th) => {
    const btn = th.querySelector('.sort-btn');
    const key = btn.dataset.sort;
    const arrow = th.querySelector('.sort-arrow');
    if (arrow) arrow.textContent = key === sortState.key ? (sortState.dir === 'asc' ? '▲' : '▼') : '';
    th.setAttribute('aria-sort', key === sortState.key ? (sortState.dir === 'asc' ? 'ascending' : 'descending') : 'none');
  });
}

function setupSortable(tableId, sortState, onSort) {
  document.querySelectorAll('#' + tableId + ' th.sortable .sort-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      toggleSort(btn.dataset.sort, sortState);
      onSort();
      persistState();
    });
  });
}

function renderEmptyRow(tbody, colspan, msg) {
  const tr = document.createElement('tr');
  const td = document.createElement('td');
  td.className = 'table-empty';
  td.colSpan = colspan;
  td.textContent = msg;
  tr.appendChild(td);
  tbody.appendChild(tr);
}

async function refreshOverview() {
  const data = await fetchJSON('api/overview');
  document.getElementById('kpi-up').textContent = fmtBytes(data.total_up);
  document.getElementById('kpi-down').textContent = fmtBytes(data.total_down);
  document.getElementById('kpi-total').textContent = fmtBytes((data.total_up || 0) + (data.total_down || 0));
  document.getElementById('kpi-users').textContent = data.users.length;
  document.getElementById('kpi-online').textContent = `在线 ${data.users.filter((u) => u.online).length}`;

  const tbody = document.querySelector('#users-table tbody');
  tbody.innerHTML = '';
  const users = sortRows(data.users, overviewSortVal, overviewSort);
  if (!users.length) {
    renderEmptyRow(tbody, 8, '暂无用户数据');
  }
  for (const u of users) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${protoBadge(u.protocol)}</td>` +
      `<td>${escapeHtml(u.username)}</td>` +
      `<td class="mono">${fmtBytes(u.uplink)}</td>` +
      `<td class="mono">${fmtBytes(u.downlink)}</td>` +
      `<td class="mono">${fmtBytes(u.total)}</td>` +
      `<td class="mono">${fmtBytes(u.lifetime_total)}</td>` +
      `<td><span class="badge ${u.online ? 'online' : ''}">${u.online ? '在线' : '离线'}</span></td>` +
      `<td class="mono">${fmtTime(u.last_seen)}</td>`;
    tbody.appendChild(tr);
  }
  updateSortIndicators('users-table', overviewSort);
}

let allUsers = [];

// Multi-select dropdown filter (checkbox list in a dropdown panel).
function multiSelect(el, placeholder, onChange) {
  const state = { values: [], options: [], open: false };
  el.innerHTML = '';

  const trigger = document.createElement('button');
  trigger.type = 'button';
  trigger.className = 'ms-trigger';
  trigger.setAttribute('aria-haspopup', 'true');
  trigger.setAttribute('aria-expanded', 'false');
  const label = document.createElement('span');
  label.className = 'ms-label';
  trigger.appendChild(label);
  const caret = document.createElement('span');
  caret.className = 'ms-caret';
  caret.setAttribute('aria-hidden', 'true');
  caret.textContent = '▾';
  trigger.appendChild(caret);

  const menu = document.createElement('div');
  menu.className = 'ms-menu';
  const items = document.createElement('div');
  items.className = 'ms-items';
  menu.appendChild(items);

  el.appendChild(trigger);
  el.appendChild(menu);

  function setOpen(open) {
    state.open = open;
    el.classList.toggle('open', open);
    trigger.setAttribute('aria-expanded', String(open));
  }

  function updateLabel() {
    if (state.values.length === 0) { label.textContent = placeholder; return; }
    const names = state.values.map((v) => {
      const o = state.options.find((x) => x.value === v);
      return o ? o.label : v;
    });
    label.textContent = names.length <= 2 ? names.join('、') : `已选 ${names.length} 项`;
  }

  function render() {
    items.innerHTML = '';
    for (const o of state.options) {
      const lab = document.createElement('label');
      lab.className = 'ms-item';
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.value = o.value;
      cb.checked = state.values.includes(o.value);
      cb.addEventListener('change', () => {
        if (cb.checked) {
          if (!state.values.includes(o.value)) state.values.push(o.value);
        } else {
          state.values = state.values.filter((v) => v !== o.value);
        }
        updateLabel();
        if (onChange) onChange();
      });
      const span = document.createElement('span');
      span.textContent = o.label;
      lab.appendChild(cb);
      lab.appendChild(span);
      items.appendChild(lab);
    }
    updateLabel();
  }

  trigger.addEventListener('click', (e) => {
    e.stopPropagation();
    setOpen(!state.open);
  });
  trigger.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      setOpen(false);
      trigger.focus();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      setOpen(true);
      const first = items.querySelector('input');
      if (first) first.focus();
    }
  });
  document.addEventListener('click', (e) => {
    if (!el.contains(e.target)) setOpen(false);
  });
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { setOpen(false); trigger.focus(); }
  });

  return {
    setOptions(options) {
      state.options = options;
      state.values = state.values.filter((v) => options.some((o) => o.value === v));
      render();
    },
    setValues(values) {
      state.values = values.slice();
      render();
    },
    getValues() { return state.values.slice(); },
    clear() { state.values = []; render(); },
    isEmpty() { return state.values.length === 0; },
  };
}

function distinctProtocols(users) {
  const out = [];
  for (const u of users) if (!out.includes(u.protocol)) out.push(u.protocol);
  return out;
}

function distinctUsernames(users) {
  const out = [];
  for (const u of users) if (!out.includes(u.username)) out.push(u.username);
  return out;
}

const CONN_PAGE = 50;
const CONN_MAX = 1000;
let connLimit = CONN_PAGE;

const connProtocolMS = multiSelect(document.getElementById('conn-protocol'), '全部协议', () => { connLimit = CONN_PAGE; refreshConnections().catch(() => {}); persistState(); });
const connUserMS = multiSelect(document.getElementById('conn-user'), '全部用户', () => { connLimit = CONN_PAGE; refreshConnections().catch(() => {}); persistState(); });
const connStatusMS = multiSelect(document.getElementById('conn-status'), '全部状态', () => { connLimit = CONN_PAGE; refreshConnections().catch(() => {}); persistState(); });
const histProtocolMS = multiSelect(document.getElementById('hist-protocol'), '全部协议', () => { refreshHistory().catch(() => {}); persistState(); });
const histUserMS = multiSelect(document.getElementById('hist-user'), '全部用户', () => { refreshHistory().catch(() => {}); persistState(); });
const chartUserMS = multiSelect(document.getElementById('chart-user'), '全部用户', () => { refreshChart().catch(() => {}); persistState(); });

connStatusMS.setOptions([
  { value: 'direct', label: '直连' },
  { value: 'warp', label: 'WARP' },
  { value: 'blocked', label: '封禁' },
  { value: 'empty', label: '未知' },
]);

function buildFilters(users) {
  allUsers = users;
  const protos = distinctProtocols(users).map((p) => ({ value: p, label: protoLabel(p) }));
  const names = distinctUsernames(users).map((n) => ({ value: n, label: n }));
  connProtocolMS.setOptions(protos);
  connUserMS.setOptions(names);
  histProtocolMS.setOptions(protos);
  histUserMS.setOptions(names);
  chartUserMS.setOptions(names);
}

function connQueryParams() {
  const qs = [`limit=${connLimit}`];
  for (const p of connProtocolMS.getValues()) qs.push('protocol=' + encodeURIComponent(p));
  for (const u of connUserMS.getValues()) qs.push('username=' + encodeURIComponent(u));
  for (const s of connStatusMS.getValues()) qs.push('status=' + encodeURIComponent(s));
  return qs;
}

async function refreshConnections() {
  const data = await fetchJSON('api/connections?' + connQueryParams().join('&'));
  const tbody = document.querySelector('#conn-table tbody');
  tbody.innerHTML = '';
  if (!data.connections.length) {
    renderEmptyRow(tbody, 6, '暂无连接记录');
  }
  for (const c of data.connections) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td class="mono">${fmtTime(c.ts)}</td>` +
      `<td>${protoBadge(c.protocol)}</td>` +
      `<td>${escapeHtml(c.username) || '—'}</td>` +
      `<td>${statusBadge(c.status)}</td>` +
      `<td class="mono">${escapeHtml(c.source) || '—'}${c.source_geo ? ' <span class="geo">[' + escapeHtml(c.source_geo) + ']</span>' : ''}</td>` +
      `<td class="mono">${escapeHtml(c.target)}</td>`;
    tbody.appendChild(tr);
  }
  updateConnMore(data.connections.length);
}

function updateConnMore(count) {
  const btn = document.getElementById('conn-more');
  btn.textContent = `加载更多（已显示 ${count} 条）`;
  btn.style.display = (connLimit < CONN_MAX && count >= connLimit) ? '' : 'none';
}

function histRange() {
  const mode = document.getElementById('hist-range').value;
  const now = Math.floor(Date.now() / 1000);
  let start = 0;
  let end = now;
  if (mode === 'custom') {
    const from = document.getElementById('hist-from').value;
    const to = document.getElementById('hist-to').value;
    if (from) start = Math.floor(new Date(from + 'T00:00:00').getTime() / 1000);
    if (to) end = Math.floor(new Date(to + 'T23:59:59').getTime() / 1000);
    if (!from && !to) start = end - 30 * 86400;
  } else {
    start = end - parseInt(mode, 10) * 86400;
  }
  return { start, end };
}

let lastHistUsers = [];

async function refreshHistory() {
  const { start, end } = histRange();
  const qs = [`start=${start}`, `end=${end}`];
  for (const p of histProtocolMS.getValues()) qs.push('protocol=' + encodeURIComponent(p));
  for (const u of histUserMS.getValues()) qs.push('username=' + encodeURIComponent(u));
  const data = await fetchJSON('api/history?' + qs.join('&'));
  document.getElementById('hist-up').textContent = fmtBytes(data.total_up);
  document.getElementById('hist-down').textContent = fmtBytes(data.total_down);
  document.getElementById('hist-total').textContent = fmtBytes((data.total_up || 0) + (data.total_down || 0));

  const tbody = document.querySelector('#hist-table tbody');
  tbody.innerHTML = '';
  const users = sortRows(data.users || [], histSortVal, histSort);
  if (!users.length) {
    renderEmptyRow(tbody, 5, '该时间范围内暂无数据');
  }
  for (const u of users) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${protoBadge(u.protocol)}</td>` +
      `<td>${escapeHtml(u.username) || '—'}</td>` +
      `<td class="mono">${fmtBytes(u.uplink)}</td>` +
      `<td class="mono">${fmtBytes(u.downlink)}</td>` +
      `<td class="mono">${fmtBytes(u.uplink + u.downlink)}</td>`;
    tbody.appendChild(tr);
  }
  lastHistUsers = users;
  updateSortIndicators('hist-table', histSort);
  drawHistoryChart(lastHistUsers);
}

function protoColor(p) {
  if (p === 'vmess') return '#7c5cff';
  if (p === 'anytls') return '#ff8c4f';
  return '#4f8cff';
}

function shortName(s) {
  return s.length > 12 ? s.slice(0, 12) + '…' : s;
}

function appendSrTable(el, headers, rows) {
  const table = document.createElement('table');
  table.className = 'sr-only';
  const thead = document.createElement('thead');
  const htr = document.createElement('tr');
  for (const h of headers) {
    const th = document.createElement('th');
    th.textContent = h;
    htr.appendChild(th);
  }
  thead.appendChild(htr);
  table.appendChild(thead);
  const tbody = document.createElement('tbody');
  for (const cells of rows) {
    const tr = document.createElement('tr');
    for (const c of cells) {
      const td = document.createElement('td');
      td.textContent = c;
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  el.appendChild(table);
}

// drawHistoryChart renders a per-user comparison bar chart for the selected
// range: x-axis is users, y-axis is traffic, stacked by protocol.
function drawHistoryChart(users) {
  const el = document.getElementById('hist-chart');
  el.innerHTML = '';
  if (!users.length) {
    el.textContent = '该时间范围内暂无数据';
    el.style.color = 'var(--muted)';
    el.style.textAlign = 'center';
    el.style.padding = '24px';
    return;
  }
  el.style.color = '';
  el.style.textAlign = '';
  el.style.padding = '';

  const byUser = new Map();
  for (const u of users) {
    const name = u.username || '(无用户)';
    if (!byUser.has(name)) byUser.set(name, []);
    byUser.get(name).push(u);
  }
  const names = [...byUser.keys()].sort();

  const srRows = [];
  for (const name of names) {
    for (const u of byUser.get(name)) {
      srRows.push([name, protoLabel(u.protocol), fmtBytes(u.uplink + u.downlink)]);
    }
  }
  appendSrTable(el, ['用户', '协议', '流量'], srRows);

  const svgNS = 'http://www.w3.org/2000/svg';
  const maxBarW = 140;
  const minBarW = 12;
  const gap = 14;
  const height = 260;
  const margin = { top: 6, right: 12, bottom: 44, left: 56 };
  const containerW = Math.max(el.clientWidth - 16, 320);
  const available = containerW - margin.left - margin.right;
  let barW = (available + gap) / names.length - gap;
  if (barW > maxBarW) barW = maxBarW;
  if (barW < minBarW) barW = minBarW;
  const plotW = names.length * (barW + gap) - gap;
  const w = Math.max(containerW, margin.left + plotW + margin.right);
  const startX = margin.left + Math.max(0, (w - margin.left - margin.right - plotW) / 2);
  const plotH = height - margin.top - margin.bottom;

  const max = Math.max(1, ...names.map((name) =>
    byUser.get(name).reduce((s, u) => s + u.uplink + u.downlink, 0)));

  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('width', w);
  svg.setAttribute('height', height);
  svg.classList.add('chart-fade');

  const yTicks = 4;
  for (let i = 0; i <= yTicks; i++) {
    const val = (max / yTicks) * i;
    const y = margin.top + plotH - (val / max) * plotH;
    const line = document.createElementNS(svgNS, 'line');
    line.setAttribute('x1', margin.left);
    line.setAttribute('y1', y);
    line.setAttribute('x2', w - margin.right);
    line.setAttribute('y2', y);
    line.setAttribute('stroke', '#262d36');
    line.setAttribute('stroke-width', '1');
    svg.appendChild(line);
    svg.appendChild(axisText(svgNS, fmtBytes(val), margin.left - 6, y + 3, 'end'));
  }

  names.forEach((name, i) => {
    const x = startX + i * (barW + gap);
    const segs = byUser.get(name);
    const totals = segs.map((s) => s.uplink + s.downlink);
    const grand = totals.reduce((a, b) => a + b, 0);
    let tip = `${name} 总计 ${fmtBytes(grand)}`;
    for (const s of segs) tip += `\n${protoLabel(s.protocol)} ${fmtBytes(s.uplink + s.downlink)}`;
    let yCursor = margin.top + plotH;
    const bars = [];
    for (let k = 0; k < segs.length; k++) {
      const h = (totals[k] / max) * plotH;
      yCursor -= h;
      const isTop = k === segs.length - 1;
      const r = rect(svgNS, x, yCursor, barW, h, protoColor(segs[k].protocol), isTop ? 3 : 0);
      r.setAttribute('fill-opacity', '0.9');
      r.appendChild(titleEl(svgNS, tip));
      svg.appendChild(r);
      bars.push(r);
    }
    bars.forEach((r) => {
      r.addEventListener('mouseenter', () => bars.forEach((b) => b.setAttribute('fill-opacity', '1')));
      r.addEventListener('mouseleave', () => bars.forEach((b) => b.setAttribute('fill-opacity', '0.9')));
    });
    svg.appendChild(axisText(svgNS, shortName(name), x + barW / 2, margin.top + plotH + 16, 'middle'));
  });

  const legend = document.createElement('div');
  legend.style.marginTop = '6px';
  legend.style.fontSize = '12px';
  legend.style.color = 'var(--muted)';
  const protos = [...new Set(users.map((u) => u.protocol))];
  legend.innerHTML = protos.map((p) =>
    `<span style="color:${protoColor(p)}">■</span> ${protoLabel(p)}`).join(' &nbsp; ');
  el.appendChild(svg);
  el.appendChild(legend);
}

function protoLabel(p) { return p === 'vmess' ? 'VMess' : (p === 'anytls' ? 'AnyTLS' : p); }

async function refreshChart() {
  const hours = parseInt(document.getElementById('chart-hours').value, 10) || 24;
  const selected = chartUserMS.getValues();
  const data = await fetchJSON('api/traffic?hours=' + hours);
  const series = data.series || {};

  const now = new Date();
  const nowHour = Math.floor(now.getTime() / 3600000) * 3600;
  const startHour = nowHour - (hours - 1) * 3600;
  const buckets = [];
  for (let h = startHour; h <= nowHour; h += 3600) {
    buckets.push({ hour: h, up: 0, down: 0 });
  }
  const idx = {};
  buckets.forEach((b, i) => { idx[b.hour] = i; });

  const selSet = new Set(selected);
  const all = selected.length === 0;
  for (const key in series) {
    if (!all) {
      const uname = key.slice(key.indexOf(':') + 1);
      if (!selSet.has(uname)) continue;
    }
    for (const pt of series[key]) {
      const i = idx[pt.hour];
      if (i != null) { buckets[i].up += pt.uplink; buckets[i].down += pt.downlink; }
    }
  }

  drawChart(buckets);
}

function pickLabelStep(count, bw) {
  if (count <= 24) return 1;
  const minStep = Math.ceil(46 / bw);
  const candidates = [1, 2, 3, 4, 6, 8, 12, 24];
  for (const c of candidates) if (c >= minStep) return c;
  return 48;
}

// monotoneSmooth 用 Fritsch–Carlson 单调三次插值把等间距点连成平滑曲线，
// 生成不包含起点的 C 贝塞尔段，避免峰值处过冲。
function monotoneSmooth(points) {
  const n = points.length;
  if (n < 2) return '';
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  const dx = new Array(n - 1), dy = new Array(n - 1), m = new Array(n - 1);
  for (let i = 0; i < n - 1; i++) {
    dx[i] = xs[i + 1] - xs[i];
    dy[i] = ys[i + 1] - ys[i];
    m[i] = dy[i] / dx[i];
  }
  const t = new Array(n);
  t[0] = m[0];
  t[n - 1] = m[n - 2];
  for (let i = 1; i < n - 1; i++) t[i] = (m[i - 1] + m[i]) / 2;
  for (let i = 1; i < n - 1; i++) if (m[i - 1] * m[i] <= 0) t[i] = 0;
  for (let i = 0; i < n - 1; i++) {
    if (dy[i] === 0) {
      t[i] = 0;
      t[i + 1] = 0;
    } else {
      const a = t[i] / m[i];
      const b = t[i + 1] / m[i];
      const s = a * a + b * b;
      if (s > 9) {
        const k = 3 / Math.sqrt(s);
        t[i] = k * a * m[i];
        t[i + 1] = k * b * m[i];
      }
    }
  }
  let d = '';
  for (let i = 0; i < n - 1; i++) {
    const x1 = xs[i] + dx[i] / 3;
    const y1 = ys[i] + t[i] * dx[i] / 3;
    const x2 = xs[i + 1] - dx[i] / 3;
    const y2 = ys[i + 1] - t[i + 1] * dx[i] / 3;
    d += ` C ${x1} ${y1}, ${x2} ${y2}, ${xs[i + 1]} ${ys[i + 1]}`;
  }
  return d;
}

function linePath(points) {
  if (!points.length) return '';
  if (prefersReducedMotion) {
    return points.map((p, i) => (i === 0 ? 'M' : 'L') + p.x + ' ' + p.y).join(' ');
  }
  return `M ${points[0].x} ${points[0].y}` + monotoneSmooth(points);
}

function areaPath(topPts, bottomPts) {
  if (!topPts.length) return '';
  return linePath(topPts) + linePath([...bottomPts].reverse()).replace(/^M/, 'L') + ' Z';
}

function drawChart(buckets) {
  const el = document.getElementById('chart');
  el.innerHTML = '';
  const max = Math.max(1, ...buckets.map((b) => b.up + b.down));

  const svgNS = 'http://www.w3.org/2000/svg';
  const width = Math.max(el.clientWidth - 16, 420);
  const height = 264;
  const margin = { top: 6, right: 6, bottom: 44, left: 56 };
  const plotW = width - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const bw = plotW / buckets.length;
  const barCenter = (i) => margin.left + i * bw + bw / 2;
  const hourOf = (i) => new Date(buckets[i].hour * 1000).getHours();

  const srRows = buckets.map((b) => [fmtHourLabel(b.hour), fmtBytes(b.up), fmtBytes(b.down), fmtBytes(b.up + b.down)]);
  appendSrTable(el, ['时间', '上行', '下行', '总计'], srRows);

  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);
  svg.classList.add('chart-fade');

  const defs = document.createElementNS(svgNS, 'defs');
  defs.appendChild(makeGradient(svgNS, 'chart-grad-up', '#38d39f'));
  defs.appendChild(makeGradient(svgNS, 'chart-grad-down', '#5aa2ff'));
  svg.appendChild(defs);

  // Y 轴：刻度线与数值（含单位）
  const yTicks = 4;
  for (let i = 0; i <= yTicks; i++) {
    const val = (max / yTicks) * i;
    const y = margin.top + plotH - (val / max) * plotH;
    const line = document.createElementNS(svgNS, 'line');
    line.setAttribute('x1', margin.left);
    line.setAttribute('y1', y);
    line.setAttribute('x2', margin.left + plotW);
    line.setAttribute('y2', y);
    line.setAttribute('stroke', '#262d36');
    line.setAttribute('stroke-width', '1');
    svg.appendChild(line);
    svg.appendChild(axisText(svgNS, fmtBytes(val), margin.left - 6, y + 3, 'end'));
  }

  // 平滑堆叠面积图（上行在底部=绿，下行堆在上方=蓝）
  const xs = buckets.map((_, i) => barCenter(i));
  const y0 = margin.top + plotH;
  const yUp = buckets.map((b) => y0 - (b.up / max) * plotH);
  const yDown = buckets.map((b) => y0 - ((b.up + b.down) / max) * plotH);
  const upPts = xs.map((x, i) => ({ x, y: yUp[i] }));
  const downPts = xs.map((x, i) => ({ x, y: yDown[i] }));
  const basePts = xs.map((x) => ({ x, y: y0 }));

  const areaUp = document.createElementNS(svgNS, 'path');
  areaUp.setAttribute('d', areaPath(upPts, basePts));
  areaUp.setAttribute('fill', 'url(#chart-grad-up)');
  svg.appendChild(areaUp);

  const areaDown = document.createElementNS(svgNS, 'path');
  areaDown.setAttribute('d', areaPath(downPts, upPts));
  areaDown.setAttribute('fill', 'url(#chart-grad-down)');
  svg.appendChild(areaDown);

  const lineUp = document.createElementNS(svgNS, 'path');
  lineUp.setAttribute('d', linePath(upPts));
  lineUp.setAttribute('fill', 'none');
  lineUp.setAttribute('stroke', '#38d39f');
  lineUp.setAttribute('stroke-width', '1.5');
  lineUp.setAttribute('stroke-linejoin', 'round');
  svg.appendChild(lineUp);

  const lineDown = document.createElementNS(svgNS, 'path');
  lineDown.setAttribute('d', linePath(downPts));
  lineDown.setAttribute('fill', 'none');
  lineDown.setAttribute('stroke', '#5aa2ff');
  lineDown.setAttribute('stroke-width', '1.5');
  lineDown.setAttribute('stroke-linejoin', 'round');
  svg.appendChild(lineDown);

  if (buckets.length <= 24) {
    for (let i = 0; i < buckets.length; i++) {
      const upDot = document.createElementNS(svgNS, 'circle');
      upDot.setAttribute('cx', xs[i]); upDot.setAttribute('cy', yUp[i]); upDot.setAttribute('r', '2.5');
      upDot.setAttribute('fill', '#38d39f');
      svg.appendChild(upDot);
      const downDot = document.createElementNS(svgNS, 'circle');
      downDot.setAttribute('cx', xs[i]); downDot.setAttribute('cy', yDown[i]); downDot.setAttribute('r', '2.5');
      downDot.setAttribute('fill', '#5aa2ff');
      svg.appendChild(downDot);
    }
  }

  // 悬停引导线
  const guide = document.createElementNS(svgNS, 'line');
  guide.setAttribute('y1', margin.top);
  guide.setAttribute('y2', margin.top + plotH);
  guide.setAttribute('stroke', '#38d39f');
  guide.setAttribute('stroke-width', '1');
  guide.setAttribute('stroke-dasharray', '3 3');
  guide.setAttribute('pointer-events', 'none');
  guide.setAttribute('visibility', 'hidden');
  svg.appendChild(guide);

  // X 轴：刻度线 + 标签（对齐整点）
  const step = pickLabelStep(buckets.length, bw);
  const labeled = [];
  for (let i = 0; i < buckets.length; i++) {
    if (hourOf(i) % step === 0) labeled.push(i);
  }
  if (!labeled.includes(buckets.length - 1)) labeled.push(buckets.length - 1);

  const tickY = margin.top + plotH;
  for (const i of labeled) {
    const x = barCenter(i);
    const t = document.createElementNS(svgNS, 'line');
    t.setAttribute('x1', x); t.setAttribute('y1', tickY);
    t.setAttribute('x2', x); t.setAttribute('y2', tickY + 5);
    t.setAttribute('stroke', '#8a97a8');
    t.setAttribute('stroke-width', '1');
    svg.appendChild(t);
  }

  if (step === 1) {
    // 24h：逐小时旋转标注，午夜处显示日期
    for (let i = 0; i < buckets.length; i++) {
      const x = barCenter(i);
      const rt = document.createElementNS(svgNS, 'text');
      rt.setAttribute('x', x);
      rt.setAttribute('y', tickY + 10);
      rt.setAttribute('text-anchor', 'end');
      rt.setAttribute('class', 'axis');
      rt.setAttribute('transform', `rotate(-45 ${x} ${tickY + 10})`);
      rt.textContent = hourOf(i) === 0 ? fmtDayLabel(buckets[i].hour) : fmtClockLabel(buckets[i].hour);
      svg.appendChild(rt);
    }
  } else {
    for (const i of labeled) {
      const x = barCenter(i);
      svg.appendChild(axisText2(svgNS, fmtDayLabel(buckets[i].hour), fmtClockLabel(buckets[i].hour), x, tickY + 14));
    }
  }

  const legend = document.createElement('div');
  legend.style.marginTop = '6px';
  legend.style.fontSize = '12px';
  legend.style.color = 'var(--muted)';
  legend.innerHTML = '<span style="color:#38d39f">■</span> 上行 &nbsp; <span style="color:#5aa2ff">■</span> 下行';
  el.appendChild(svg);
  el.appendChild(legend);

  // 悬停提示浮层
  const tooltip = document.createElement('div');
  tooltip.className = 'chart-tooltip';
  tooltip.style.display = 'none';
  el.appendChild(tooltip);

  const setTip = (i, keyFocus) => {
    if (i == null || i < 0 || i >= buckets.length) {
      tooltip.style.display = 'none';
      guide.setAttribute('visibility', 'hidden');
      return;
    }
    const b = buckets[i];
    guide.setAttribute('x1', barCenter(i));
    guide.setAttribute('x2', barCenter(i));
    guide.setAttribute('visibility', 'visible');
    tooltip.innerHTML =
      `<div>${fmtHourLabel(b.hour)}</div>` +
      `<div style="color:#38d39f">上行 ${fmtBytes(b.up)}</div>` +
      `<div style="color:#5aa2ff">下行 ${fmtBytes(b.down)}</div>` +
      `<div>总计 ${fmtBytes(b.up + b.down)}</div>`;
    tooltip.style.display = 'block';
    if (keyFocus) {
      tooltip.style.left = (barCenter(i) + margin.left) + 'px';
      tooltip.style.top = margin.top + 'px';
    }
  };

  svg.addEventListener('mousemove', (e) => {
    const sRect = svg.getBoundingClientRect();
    const i = Math.floor((e.clientX - sRect.left - margin.left) / bw);
    setTip(i, false);
    const eRect = el.getBoundingClientRect();
    let tx = e.clientX - eRect.left + 14;
    let ty = e.clientY - eRect.top + 14;
    tooltip.style.left = tx + 'px';
    tooltip.style.top = ty + 'px';
    const tRect = tooltip.getBoundingClientRect();
    if (tx + tRect.width > eRect.width) tooltip.style.left = (tx - tRect.width - 28) + 'px';
    if (ty + tRect.height > eRect.height) tooltip.style.top = (ty - tRect.height - 28) + 'px';
  });
  svg.addEventListener('mouseleave', () => setTip(null));

  // 键盘可聚焦数据点（仅 24 小时视图，避免过长 Tab 序列；更大范围由 sr-only 表格提供）
  if (buckets.length <= 24) {
    buckets.forEach((b, i) => {
      const hit = document.createElementNS(svgNS, 'rect');
      hit.setAttribute('x', margin.left + i * bw);
      hit.setAttribute('y', margin.top);
      hit.setAttribute('width', Math.max(bw, 1));
      hit.setAttribute('height', plotH);
      hit.setAttribute('fill', 'transparent');
      hit.setAttribute('tabindex', '0');
      hit.setAttribute('role', 'img');
      hit.setAttribute('aria-label',
        `${fmtHourLabel(b.hour)} 上行 ${fmtBytes(b.up)}，下行 ${fmtBytes(b.down)}，总计 ${fmtBytes(b.up + b.down)}`);
      hit.addEventListener('focus', () => setTip(i, true));
      hit.addEventListener('blur', () => setTip(null));
      svg.appendChild(hit);
    });
  }
}

function axisText(svgNS, content, x, y, anchor) {
  const t = document.createElementNS(svgNS, 'text');
  t.setAttribute('x', x);
  t.setAttribute('y', y);
  t.setAttribute('text-anchor', anchor);
  t.setAttribute('class', 'axis');
  t.textContent = content;
  return t;
}

function axisText2(svgNS, line1, line2, x, y) {
  const t = document.createElementNS(svgNS, 'text');
  t.setAttribute('x', x);
  t.setAttribute('y', y);
  t.setAttribute('text-anchor', 'middle');
  t.setAttribute('class', 'axis');
  const ts1 = document.createElementNS(svgNS, 'tspan');
  ts1.setAttribute('x', x);
  ts1.textContent = line1;
  const ts2 = document.createElementNS(svgNS, 'tspan');
  ts2.setAttribute('x', x);
  ts2.setAttribute('dy', '12');
  ts2.textContent = line2;
  t.appendChild(ts1);
  t.appendChild(ts2);
  return t;
}

function rect(svgNS, x, y, w, h, fill, rx) {
  const r = document.createElementNS(svgNS, 'rect');
  r.setAttribute('x', x);
  r.setAttribute('y', y);
  r.setAttribute('width', Math.max(w, 0.5));
  r.setAttribute('height', Math.max(h, 0));
  r.setAttribute('fill', fill);
  if (rx) r.setAttribute('rx', rx);
  return r;
}

function makeGradient(svgNS, id, color) {
  const g = document.createElementNS(svgNS, 'linearGradient');
  g.setAttribute('id', id);
  g.setAttribute('x1', '0'); g.setAttribute('y1', '0');
  g.setAttribute('x2', '0'); g.setAttribute('y2', '1');
  const s1 = document.createElementNS(svgNS, 'stop');
  s1.setAttribute('offset', '0%');
  s1.setAttribute('stop-color', color);
  s1.setAttribute('stop-opacity', '0.55');
  const s2 = document.createElementNS(svgNS, 'stop');
  s2.setAttribute('offset', '100%');
  s2.setAttribute('stop-color', color);
  s2.setAttribute('stop-opacity', '0.06');
  g.appendChild(s1);
  g.appendChild(s2);
  return g;
}

function titleEl(svgNS, content) {
  const t = document.createElementNS(svgNS, 'title');
  t.textContent = content;
  return t;
}

// ---- 用户配置页 ----
let allConfigs = [];
let configsLoaded = false;
let configSearch = '';
let configProto = '';

function configSecretLabel(c) {
  return c.secret_label || (c.protocol === 'vmess' ? 'UUID' : '密码');
}

function configText(c) {
  const lines = [];
  lines.push('协议: ' + protoLabel(c.protocol));
  lines.push('用户: ' + c.username);
  if (c.address) lines.push('地址: ' + c.address);
  if (c.port) lines.push('端口: ' + c.port);
  lines.push(configSecretLabel(c) + ': ' + c.secret);
  if (c.path) lines.push('路径: ' + c.path);
  if (c.sni) lines.push('SNI: ' + c.sni);
  if (c.transport) lines.push('传输方式: ' + c.transport);
  if (c.tls) lines.push('Over TLS: ' + c.tls);
  if (c.aead) lines.push('VMessAEAD: ' + c.aead);
  if (c.skip_cert_check) lines.push('跳过证书检查: ' + c.skip_cert_check);
  if (c.link) lines.push('导入链接: ' + c.link);
  if (c.surge) lines.push('Surge: ' + c.surge);
  return lines.join('\n');
}

function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text);
  }
  return new Promise((resolve, reject) => {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); resolve(); }
    catch (e) { reject(e); }
    document.body.removeChild(ta);
  });
}

function toast(msg) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    t.setAttribute('role', 'status');
    t.setAttribute('aria-live', 'polite');
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('show'), 1600);
}

function visibleConfigs() {
  const q = configSearch.trim().toLowerCase();
  return allConfigs.filter((c) => {
    if (configProto && c.protocol !== configProto) return false;
    if (q && c.username.toLowerCase().indexOf(q) < 0) return false;
    return true;
  });
}

function configKV(label, value) {
  if (value == null || value === '') return '';
  return '<div class="config-kv"><span class="config-k">' + label + '</span>' +
    '<span class="config-v mono">' + escapeHtml(value) + '</span></div>';
}

function configCard(c) {
  const card = document.createElement('div');
  card.className = 'config-card';
  card.innerHTML =
    '<div class="config-card-head">' +
      '<span>' + protoBadge(c.protocol) + ' <span class="config-user">' + escapeHtml(c.username) + '</span></span>' +
      '<button class="btn copy-btn">复制</button>' +
    '</div>' +
    '<div class="config-card-body">' +
      configKV('地址', c.address) +
      configKV('端口', c.port) +
      configKV(configSecretLabel(c), c.secret) +
      configKV('路径', c.path) +
      configKV('SNI', c.sni) +
      configKV('传输方式', c.transport) +
      configKV('Over TLS', c.tls) +
      configKV('VMessAEAD', c.aead) +
      configKV('跳过证书检查', c.skip_cert_check) +
    '</div>' +
    (c.link ? '<div class="config-link mono" title="' + escapeHtml(c.link) + '">' + escapeHtml(c.link) + '</div>' : '');
  card.querySelector('.copy-btn').addEventListener('click', () => {
    copyText(configText(c)).then(() => toast('已复制 ' + c.username + ' 配置')).catch(() => toast('复制失败'));
  });
  return card;
}

function renderConfigs() {
  const container = document.getElementById('config-groups');
  const list = visibleConfigs();
  container.innerHTML = '';
  if (!list.length) {
    container.innerHTML = '<div class="empty">无匹配用户</div>';
    return;
  }
  const protos = [...new Set(list.map((c) => c.protocol))];
  for (const p of protos) {
    const users = list.filter((c) => c.protocol === p);
    const group = document.createElement('div');
    group.className = 'config-group';
    const head = document.createElement('div');
    head.className = 'config-group-head';
    head.innerHTML = protoBadge(p) + ' <span class="config-group-count">' + users.length + ' 个用户</span>';
    group.appendChild(head);
    const grid = document.createElement('div');
    grid.className = 'config-grid';
    for (const c of users) grid.appendChild(configCard(c));
    group.appendChild(grid);
    container.appendChild(group);
  }
}

async function refreshConfigs() {
  const data = await fetchJSON('api/configs');
  allConfigs = data.configs || [];
  configsLoaded = true;
  renderConfigs();
}

// ---- URL 状态同步 ----
let currentPage = 'dashboard';
let currentSubtab = 'conn';

function showSubtab(key) {
  currentSubtab = key === 'hist' ? 'hist' : 'conn';
  document.getElementById('view-conn').hidden = currentSubtab !== 'conn';
  document.getElementById('view-hist').hidden = currentSubtab !== 'hist';
  document.querySelectorAll('.sub-tab').forEach((t) => {
    const active = t.dataset.subtab === currentSubtab;
    t.classList.toggle('active', active);
    t.setAttribute('aria-selected', String(active));
  });
  if (currentSubtab === 'hist' && lastHistUsers.length) {
    drawHistoryChart(lastHistUsers);
  }
}

function parseUrlState() {
  const raw = location.hash || '';
  const m = raw.match(/^#\/([^?]*)(\?(.*))?$/);
  const page = (m && m[1]) || 'dashboard';
  const params = new URLSearchParams(m && m[3] ? m[3] : '');
  return { page, params };
}

function writeArr(params, key, arr) {
  params.delete(key);
  for (const v of arr) params.append(key, v);
}

function collectParams() {
  const params = new URLSearchParams();
  params.set('osort', overviewSort.key);
  params.set('odir', overviewSort.dir);
  params.set('hours', document.getElementById('chart-hours').value);
  writeArr(params, 'cuser', chartUserMS.getValues());
  writeArr(params, 'cproto', connProtocolMS.getValues());
  writeArr(params, 'connuser', connUserMS.getValues());
  writeArr(params, 'connstatus', connStatusMS.getValues());
  params.set('hrange', document.getElementById('hist-range').value);
  const hf = document.getElementById('hist-from').value;
  const ht = document.getElementById('hist-to').value;
  if (hf) params.set('hfrom', hf);
  if (ht) params.set('hto', ht);
  writeArr(params, 'hproto', histProtocolMS.getValues());
  writeArr(params, 'huser', histUserMS.getValues());
  params.set('hsort', histSort.key);
  params.set('hdir', histSort.dir);
  if (currentSubtab === 'hist') params.set('subtab', 'hist');
  if (configSearch) params.set('search', configSearch);
  if (configProto) params.set('proto', configProto);
  return params;
}

function persistState() {
  const params = collectParams();
  const newHash = '#/' + currentPage + (params.toString() ? '?' + params.toString() : '');
  if (location.hash !== newHash) {
    history.replaceState(null, '', newHash);
  }
}

function showPage(page) {
  currentPage = page;
  document.getElementById('page-dashboard').hidden = page !== 'dashboard';
  document.getElementById('page-configs').hidden = page !== 'configs';
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.page === page));
  document.getElementById('footer-note').textContent =
    page === 'configs' ? '配置数据按需读取，点击「刷新」获取最新' : '数据每 15 秒自动刷新';
}

async function ensureConfigs() {
  if (!configsLoaded) await refreshConfigs();
  renderConfigs();
}

function applyUrlState() {
  const { page, params } = parseUrlState();
  showPage(page);
  showSubtab(params.get('subtab') === 'hist' ? 'hist' : 'conn');

  const sk = params.get('osort');
  if (sk) overviewSort = { key: sk, dir: params.get('odir') === 'asc' ? 'asc' : 'desc' };

  const hours = params.get('hours');
  if (hours) document.getElementById('chart-hours').value = hours;
  chartUserMS.setValues(params.getAll('cuser'));

  connProtocolMS.setValues(params.getAll('cproto'));
  connUserMS.setValues(params.getAll('connuser'));
  connStatusMS.setValues(params.getAll('connstatus'));

  const hrange = params.get('hrange');
  if (hrange) document.getElementById('hist-range').value = hrange;
  document.getElementById('hist-from').value = params.get('hfrom') || '';
  document.getElementById('hist-to').value = params.get('hto') || '';
  document.getElementById('hist-custom').style.display = hrange === 'custom' ? 'inline' : 'none';
  histProtocolMS.setValues(params.getAll('hproto'));
  histUserMS.setValues(params.getAll('huser'));
  const hsk = params.get('hsort');
  if (hsk) histSort = { key: hsk, dir: params.get('hdir') === 'asc' ? 'asc' : 'desc' };

  const search = params.get('search');
  if (search != null) {
    configSearch = search;
    document.getElementById('config-search').value = search;
  }
  configProto = params.get('proto') || '';
  document.querySelectorAll('#config-proto .seg-btn').forEach((x) => x.classList.toggle('active', x.dataset.proto === configProto));

  refreshOverview().catch(() => {});
  refreshConnections().catch(() => {});
  refreshChart().catch(() => {});
  refreshHistory().catch(() => {});
  if (page === 'configs') ensureConfigs().catch(() => {});
}

async function bootstrap() {
  const ov = await fetchJSON('api/overview');
  buildFilters(ov.users);
  applyUrlState();
}

function switchPage(page) {
  const params = collectParams();
  history.pushState(null, '', '#/' + page + (params.toString() ? '?' + params.toString() : ''));
  showPage(page);
  if (page === 'configs') ensureConfigs().catch(() => {});
}

document.getElementById('chart-hours').addEventListener('change', () => { refreshChart().catch(() => {}); persistState(); });
document.getElementById('conn-more').addEventListener('click', () => {
  connLimit = Math.min(connLimit + CONN_PAGE, CONN_MAX);
  refreshConnections().catch(() => {});
});
document.getElementById('hist-range').addEventListener('change', () => {
  document.getElementById('hist-custom').style.display =
    document.getElementById('hist-range').value === 'custom' ? 'inline' : 'none';
  refreshHistory().catch(() => {});
  persistState();
});
document.getElementById('hist-from').addEventListener('change', () => {
  refreshHistory().catch(() => {});
  persistState();
});
document.getElementById('hist-to').addEventListener('change', () => {
  refreshHistory().catch(() => {});
  persistState();
});
document.getElementById('clear-chart-filters').addEventListener('click', () => {
  chartUserMS.clear();
  refreshChart().catch(() => {});
  persistState();
});
document.getElementById('clear-conn-filters').addEventListener('click', () => {
  connProtocolMS.clear();
  connUserMS.clear();
  connStatusMS.clear();
  connLimit = CONN_PAGE;
  refreshConnections().catch(() => {});
  persistState();
});
document.getElementById('clear-hist-filters').addEventListener('click', () => {
  histProtocolMS.clear();
  histUserMS.clear();
  document.getElementById('hist-range').value = '7';
  document.getElementById('hist-custom').style.display = 'none';
  refreshHistory().catch(() => {});
  persistState();
});

setupSortable('users-table', overviewSort, () => { refreshOverview().catch(() => {}); });
setupSortable('hist-table', histSort, () => { refreshHistory().catch(() => {}); });

document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', (e) => {
  if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
  e.preventDefault();
  switchPage(t.dataset.page);
}));
document.querySelectorAll('.sub-tab').forEach((t) => t.addEventListener('click', () => {
  showSubtab(t.dataset.subtab);
  persistState();
}));
document.getElementById('config-refresh').addEventListener('click', () => {
  const btn = document.getElementById('config-refresh');
  btn.disabled = true;
  btn.textContent = '刷新中…';
  refreshConfigs()
    .then(() => toast('已刷新 · ' + allConfigs.length + ' 个用户'))
    .catch(() => toast('刷新失败'))
    .finally(() => { btn.disabled = false; btn.textContent = '刷新'; });
});
document.getElementById('config-copy-all').addEventListener('click', () => {
  const list = visibleConfigs();
  const text = list.map(configText).join('\n\n');
  if (!text) { toast('无匹配用户'); return; }
  copyText(text).then(() => toast('已复制 ' + list.length + ' 个用户配置')).catch(() => toast('复制失败'));
});
document.getElementById('config-search').addEventListener('input', (e) => {
  configSearch = e.target.value;
  renderConfigs();
  persistState();
});
document.getElementById('logout-btn').addEventListener('click', async () => {
  try { await fetch('api/logout', { method: 'POST', cache: 'no-store' }); } catch (_) {}
  window.location.replace('login');
});
document.querySelectorAll('#config-proto .seg-btn').forEach((b) => b.addEventListener('click', () => {
  configProto = b.dataset.proto;
  document.querySelectorAll('#config-proto .seg-btn').forEach((x) => x.classList.toggle('active', x === b));
  renderConfigs();
  persistState();
}));

window.addEventListener('hashchange', () => applyUrlState());

let resizeTimer;
window.addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    refreshChart().catch(() => {});
    drawHistoryChart(lastHistUsers);
  }, 200);
});

function shouldSkipAutoRefresh() {
  const ae = document.activeElement;
  if (!ae) return false;
  return ae.matches('input, select, textarea, .ms-trigger');
}

setInterval(() => {
  if (shouldSkipAutoRefresh()) return;
  refreshOverview().catch(() => {});
  refreshConnections().catch(() => {});
}, 15000);

bootstrap().catch(() => {
  document.body.innerHTML = '<div style="padding:40px;text-align:center;color:#8a96a3">面板加载失败，请稍后重试</div>';
});
