function fmtBytes(n) {
  if (n == null) return '—';
  if (n < 1024) return n + ' B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < units.length - 1);
  return n.toFixed(n >= 100 ? 0 : (n >= 10 ? 1 : 2)) + ' ' + units[i];
}

function fmtTime(ts) {
  if (!ts) return '—';
  const d = new Date(ts * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function fmtHourLabel(hour) {
  const d = new Date(hour * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:00`;
}

function fmtDayLabel(hour) {
  const d = new Date(hour * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function fmtClockLabel(hour) {
  const d = new Date(hour * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${p(d.getHours())}:00`;
}

async function fetchJSON(url) {
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error(res.statusText);
  return res.json();
}

function protoBadge(p) {
  const label = p === 'vmess' ? 'VMess' : (p === 'anytls' ? 'AnyTLS' : p);
  return `<span class="badge ${p}">${label}</span>`;
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

async function refreshOverview() {
  const data = await fetchJSON('api/overview');
  document.getElementById('total-up').textContent = fmtBytes(data.total_up);
  document.getElementById('total-down').textContent = fmtBytes(data.total_down);
  document.getElementById('total-users').textContent = data.users.length;

  const tbody = document.querySelector('#users-table tbody');
  tbody.innerHTML = '';
  for (const u of data.users) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${protoBadge(u.protocol)}</td>` +
      `<td>${escapeHtml(u.username)}</td>` +
      `<td class="mono">${fmtBytes(u.uplink)}</td>` +
      `<td class="mono">${fmtBytes(u.downlink)}</td>` +
      `<td class="mono">${fmtBytes(u.total)}</td>` +
      `<td class="mono">${fmtBytes(u.lifetime_total)}</td>` +
      `<td class="mono">${u.reset_at ? fmtTime(u.reset_at) : '—'}</td>` +
      `<td><span class="badge ${u.online ? 'online' : ''}">${u.online ? '在线' : '离线'}</span></td>` +
      `<td class="mono">${fmtTime(u.last_seen)}</td>`;
    tbody.appendChild(tr);
  }
}

let allUsers = [];

function buildConnFilters(users) {
  allUsers = users;
  const protoSel = document.getElementById('conn-protocol');
  const prevProto = protoSel.value;
  const protos = ['all'];
  protoSel.innerHTML = '';
  protoSel.appendChild(option('all', '全部协议'));
  for (const u of users) {
    if (!protos.includes(u.protocol)) {
      protos.push(u.protocol);
      protoSel.appendChild(option(u.protocol, protoLabel(u.protocol)));
    }
  }
  protoSel.value = protos.includes(prevProto) ? prevProto : 'all';
  buildConnUserOptions();
}

function buildConnUserOptions() {
  const sel = document.getElementById('conn-user');
  const prev = sel.value;
  const proto = document.getElementById('conn-protocol').value;
  const options = ['all'];
  sel.innerHTML = '';
  sel.appendChild(option('all', '全部用户'));
  for (const u of allUsers) {
    if (proto !== 'all' && u.protocol !== proto) continue;
    const val = u.protocol + ':' + u.username;
    options.push(val);
    sel.appendChild(option(val, protoLabel(u.protocol) + ' · ' + u.username));
  }
  sel.value = options.includes(prev) ? prev : 'all';
}

const CONN_PAGE = 50;
const CONN_MAX = 1000;
let connLimit = CONN_PAGE;

async function refreshConnections() {
  const proto = document.getElementById('conn-protocol').value;
  const user = document.getElementById('conn-user').value;
  const qs = [`limit=${connLimit}`];
  if (proto !== 'all') qs.push('protocol=' + encodeURIComponent(proto));
  if (user !== 'all') {
    const i = user.indexOf(':');
    qs.push('protocol=' + encodeURIComponent(user.slice(0, i)));
    qs.push('username=' + encodeURIComponent(user.slice(i + 1)));
  }
  const data = await fetchJSON('api/connections?' + qs.join('&'));
  const tbody = document.querySelector('#conn-table tbody');
  tbody.innerHTML = '';
  for (const c of data.connections) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td class="mono">${fmtTime(c.ts)}</td>` +
      `<td>${protoBadge(c.protocol)}</td>` +
      `<td>${escapeHtml(c.username) || '—'}</td>` +
      `<td>${statusBadge(c.status)}</td>` +
      `<td class="mono">${escapeHtml(c.source) || '—'}</td>` +
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

function buildUserSelect(users) {
  const sel = document.getElementById('chart-user');
  const prev = sel.value;
  const options = ['all'];
  for (const u of users) options.push(u.protocol + ':' + u.username);
  sel.innerHTML = '';
  sel.appendChild(option('all', '全部用户'));
  for (const u of users) {
    sel.appendChild(option(u.protocol + ':' + u.username, protoLabel(u.protocol) + ' · ' + u.username));
  }
  sel.value = options.includes(prev) ? prev : 'all';
}

function buildHistFilters(users) {
  const protoSel = document.getElementById('hist-protocol');
  const prevProto = protoSel.value;
  const protos = ['all'];
  protoSel.innerHTML = '';
  protoSel.appendChild(option('all', '全部协议'));
  for (const u of users) {
    if (!protos.includes(u.protocol)) {
      protos.push(u.protocol);
      protoSel.appendChild(option(u.protocol, protoLabel(u.protocol)));
    }
  }
  protoSel.value = protos.includes(prevProto) ? prevProto : 'all';
  buildHistUserOptions();
}

function buildHistUserOptions() {
  const sel = document.getElementById('hist-user');
  const prev = sel.value;
  const proto = document.getElementById('hist-protocol').value;
  const options = ['all'];
  sel.innerHTML = '';
  sel.appendChild(option('all', '全部用户'));
  for (const u of allUsers) {
    if (proto !== 'all' && u.protocol !== proto) continue;
    const val = u.protocol + ':' + u.username;
    options.push(val);
    sel.appendChild(option(val, protoLabel(u.protocol) + ' · ' + u.username));
  }
  sel.value = options.includes(prev) ? prev : 'all';
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

let lastHistDays = [];

async function refreshHistory() {
  const proto = document.getElementById('hist-protocol').value;
  const user = document.getElementById('hist-user').value;
  const { start, end } = histRange();
  const qs = [`start=${start}`, `end=${end}`];
  if (proto !== 'all') qs.push('protocol=' + encodeURIComponent(proto));
  if (user !== 'all') {
    const i = user.indexOf(':');
    qs.push('protocol=' + encodeURIComponent(user.slice(0, i)));
    qs.push('username=' + encodeURIComponent(user.slice(i + 1)));
  }
  const data = await fetchJSON('api/history?' + qs.join('&'));
  document.getElementById('hist-up').textContent = fmtBytes(data.total_up);
  document.getElementById('hist-down').textContent = fmtBytes(data.total_down);
  document.getElementById('hist-total').textContent = fmtBytes((data.total_up || 0) + (data.total_down || 0));

  const tbody = document.querySelector('#hist-table tbody');
  tbody.innerHTML = '';
  for (const u of data.users || []) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${protoBadge(u.protocol)}</td>` +
      `<td>${escapeHtml(u.username) || '—'}</td>` +
      `<td class="mono">${fmtBytes(u.uplink)}</td>` +
      `<td class="mono">${fmtBytes(u.downlink)}</td>` +
      `<td class="mono">${fmtBytes(u.uplink + u.downlink)}</td>`;
    tbody.appendChild(tr);
  }
  lastHistDays = data.days || [];
  drawHistoryChart(lastHistDays);
}

async function resetAll() {
  if (!confirm('确定要重置流量统计吗？将把「当前周期」归零，历史数据与累计总量不会丢失。')) return;
  const res = await fetch('api/reset', { method: 'POST', cache: 'no-store' });
  if (!res.ok) throw new Error(res.statusText);
  await refreshOverview();
}

function fmtDateLabel(day) {
  const d = new Date(day * 1000);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function histLabel(day, width) {
  const d = new Date(day * 1000);
  const p = (x) => String(x).padStart(2, '0');
  if (width >= 28) return `${d.getFullYear()}-${p(d.getMonth() + 1)}`;
  return `${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function niceWidth(spanDays, maxBuckets) {
  const min = Math.ceil(spanDays / maxBuckets);
  const candidates = [1, 7, 30, 90, 365];
  for (const c of candidates) { if (c >= min) return c; }
  return candidates[candidates.length - 1];
}

function bucketize(days, maxBuckets) {
  const min = days[0].day;
  const maxDay = days[days.length - 1].day;
  const spanDays = Math.max(1, Math.ceil((maxDay - min) / 86400) + 1);
  const width = niceWidth(spanDays, maxBuckets);
  const buckets = [];
  const idx = {};
  for (let t = min; t <= maxDay; t += width * 86400) {
    idx[t] = buckets.length;
    buckets.push({ day: t, up: 0, down: 0 });
  }
  for (const d of days) {
    const t = min + Math.floor((d.day - min) / (width * 86400)) * width * 86400;
    if (idx[t] != null) { buckets[idx[t]].up += d.uplink; buckets[idx[t]].down += d.downlink; }
  }
  return { buckets, width };
}

function drawHistoryChart(days) {
  const el = document.getElementById('hist-chart');
  el.innerHTML = '';
  if (!days.length) {
    el.textContent = '该时间范围内暂无数据';
    el.style.color = 'var(--muted)';
    el.style.textAlign = 'center';
    el.style.padding = '24px';
    return;
  }
  el.style.color = '';
  el.style.textAlign = '';
  el.style.padding = '';

  const { buckets, width } = bucketize(days, 90);
  const max = Math.max(1, ...buckets.map((b) => b.up + b.down));

  const svgNS = 'http://www.w3.org/2000/svg';
  const w = Math.max(el.clientWidth - 16, 420);
  const height = 220;
  const margin = { top: 6, right: 6, bottom: 26, left: 56 };
  const plotW = w - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const bw = plotW / buckets.length;

  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('width', w);
  svg.setAttribute('height', height);

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

  for (let i = 0; i < buckets.length; i++) {
    const b = buckets[i];
    const total = b.up + b.down;
    const h = (total / max) * plotH;
    const x = margin.left + i * bw;
    const y = margin.top + plotH - h;
    const tip = `${fmtDateLabel(b.day)}  上行 ${fmtBytes(b.up)}  下行 ${fmtBytes(b.down)}`;
    if (b.up > 0) {
      const r = rect(svgNS, x + 1, y, Math.max(bw - 2, 1), (b.up / max) * plotH, '#38d39f');
      r.appendChild(titleEl(svgNS, tip));
      svg.appendChild(r);
    }
    if (b.down > 0) {
      const r = rect(svgNS, x + 1, y + (b.up / max) * plotH, Math.max(bw - 2, 1), (b.down / max) * plotH, '#5aa2ff');
      r.appendChild(titleEl(svgNS, tip));
      svg.appendChild(r);
    }
  }

  const labelW = 52;
  const labelEvery = Math.max(1, Math.ceil(labelW / bw));
  for (let i = 0; i < buckets.length; i += labelEvery) {
    const x = margin.left + i * bw + bw / 2;
    if (x - labelW / 2 < 0 || x + labelW / 2 > w) continue;
    svg.appendChild(axisText(svgNS, histLabel(buckets[i].day, width), x, margin.top + plotH + 14, 'middle'));
  }

  const legend = document.createElement('div');
  legend.style.marginTop = '6px';
  legend.style.fontSize = '12px';
  legend.style.color = 'var(--muted)';
  legend.innerHTML = '<span style="color:#38d39f">■</span> 上行 &nbsp; <span style="color:#5aa2ff">■</span> 下行';
  el.appendChild(svg);
  el.appendChild(legend);
}

function option(value, text) {
  const o = document.createElement('option');
  o.value = value;
  o.textContent = text;
  return o;
}

function protoLabel(p) { return p === 'vmess' ? 'VMess' : (p === 'anytls' ? 'AnyTLS' : p); }

async function refreshChart() {
  const hours = parseInt(document.getElementById('chart-hours').value, 10) || 24;
  const selected = document.getElementById('chart-user').value;
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

  if (selected === 'all') {
    for (const key in series) {
      for (const pt of series[key]) {
        const i = idx[pt.hour];
        if (i != null) { buckets[i].up += pt.uplink; buckets[i].down += pt.downlink; }
      }
    }
  } else if (series[selected]) {
    for (const pt of series[selected]) {
      const i = idx[pt.hour];
      if (i != null) { buckets[i].up += pt.uplink; buckets[i].down += pt.downlink; }
    }
  }

  drawChart(buckets);
}

function drawChart(buckets) {
  const el = document.getElementById('chart');
  el.innerHTML = '';
  const max = Math.max(1, ...buckets.map((b) => b.up + b.down));

  const svgNS = 'http://www.w3.org/2000/svg';
  const width = Math.max(el.clientWidth - 16, 420);
  const height = 264;
  const margin = { top: 6, right: 6, bottom: 38, left: 56 };
  const plotW = width - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const bw = plotW / buckets.length;

  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);

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

  // 柱状图
  for (let i = 0; i < buckets.length; i++) {
    const b = buckets[i];
    const total = b.up + b.down;
    const h = (total / max) * plotH;
    const x = margin.left + i * bw;
    const y = margin.top + plotH - h;
    const tip = `${fmtHourLabel(b.hour)}  上行 ${fmtBytes(b.up)}  下行 ${fmtBytes(b.down)}`;
    if (b.up > 0) {
      const r = rect(svgNS, x + 1, y, Math.max(bw - 2, 1), (b.up / max) * plotH, '#38d39f');
      r.appendChild(titleEl(svgNS, tip));
      svg.appendChild(r);
    }
    if (b.down > 0) {
      const r = rect(svgNS, x + 1, y + (b.up / max) * plotH, Math.max(bw - 2, 1), (b.down / max) * plotH, '#5aa2ff');
      r.appendChild(titleEl(svgNS, tip));
      svg.appendChild(r);
    }
  }

  // X 轴：两行时间标签（日期/小时），按柱宽自适应密度，小窗口下避免重叠与裁剪
  const labelW = 42;
  const labelEvery = Math.max(1, Math.ceil(labelW / bw));
  for (let i = 0; i < buckets.length; i += labelEvery) {
    const x = margin.left + i * bw + bw / 2;
    if (x - labelW / 2 < 0 || x + labelW / 2 > width) continue;
    svg.appendChild(axisText2(svgNS, fmtDayLabel(buckets[i].hour), fmtClockLabel(buckets[i].hour), x, margin.top + plotH + 14));
  }

  const legend = document.createElement('div');
  legend.style.marginTop = '6px';
  legend.style.fontSize = '12px';
  legend.style.color = 'var(--muted)';
  legend.innerHTML = '<span style="color:#38d39f">■</span> 上行 &nbsp; <span style="color:#5aa2ff">■</span> 下行';
  el.appendChild(svg);
  el.appendChild(legend);
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

function rect(svgNS, x, y, w, h, fill) {
  const r = document.createElementNS(svgNS, 'rect');
  r.setAttribute('x', x);
  r.setAttribute('y', y);
  r.setAttribute('width', Math.max(w, 0.5));
  r.setAttribute('height', Math.max(h, 0));
  r.setAttribute('fill', fill);
  return r;
}

function titleEl(svgNS, content) {
  const t = document.createElementNS(svgNS, 'title');
  t.textContent = content;
  return t;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

async function bootstrap() {
  const ov = await fetchJSON('api/overview');
  buildUserSelect(ov.users);
  buildConnFilters(ov.users);
  buildHistFilters(ov.users);
  await refreshOverview();
  await refreshConnections();
  await refreshChart();
  await refreshHistory();
}

document.getElementById('chart-user').addEventListener('change', refreshChart);
document.getElementById('chart-hours').addEventListener('change', refreshChart);
document.getElementById('conn-protocol').addEventListener('change', () => {
  buildConnUserOptions();
  connLimit = CONN_PAGE;
  refreshConnections().catch(() => {});
});
document.getElementById('conn-user').addEventListener('change', () => {
  connLimit = CONN_PAGE;
  refreshConnections().catch(() => {});
});
document.getElementById('conn-more').addEventListener('click', () => {
  connLimit = Math.min(connLimit + CONN_PAGE, CONN_MAX);
  refreshConnections().catch(() => {});
});
document.getElementById('reset-all').addEventListener('click', () => {
  resetAll().catch(() => {});
});
document.getElementById('hist-protocol').addEventListener('change', () => {
  buildHistUserOptions();
  refreshHistory().catch(() => {});
});
document.getElementById('hist-user').addEventListener('change', () => {
  refreshHistory().catch(() => {});
});
document.getElementById('hist-range').addEventListener('change', () => {
  document.getElementById('hist-custom').style.display =
    document.getElementById('hist-range').value === 'custom' ? 'inline' : 'none';
  refreshHistory().catch(() => {});
});
document.getElementById('hist-from').addEventListener('change', () => {
  refreshHistory().catch(() => {});
});
document.getElementById('hist-to').addEventListener('change', () => {
  refreshHistory().catch(() => {});
});

let resizeTimer;
window.addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    refreshChart().catch(() => {});
    drawHistoryChart(lastHistDays);
  }, 200);
});

setInterval(() => { refreshOverview().catch(() => {}); refreshConnections().catch(() => {}); }, 15000);

bootstrap().catch(() => {
  document.body.innerHTML = '<div style="padding:40px;text-align:center;color:#8a96a3">面板加载失败，请稍后重试</div>';
});
