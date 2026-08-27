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

async function fetchJSON(url) {
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error(res.statusText);
  return res.json();
}

function protoBadge(p) {
  const label = p === 'vmess' ? 'VMess' : (p === 'anytls' ? 'AnyTLS' : p);
  return `<span class="badge ${p}">${label}</span>`;
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
      `<td><span class="badge ${u.online ? 'online' : ''}">${u.online ? '在线' : '离线'}</span></td>` +
      `<td class="mono">${fmtTime(u.last_seen)}</td>`;
    tbody.appendChild(tr);
  }
}

async function refreshConnections() {
  const data = await fetchJSON('api/connections');
  const tbody = document.querySelector('#conn-table tbody');
  tbody.innerHTML = '';
  for (const c of data.connections) {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td class="mono">${fmtTime(c.ts)}</td>` +
      `<td>${protoBadge(c.protocol)}</td>` +
      `<td>${escapeHtml(c.username) || '—'}</td>` +
      `<td class="mono">${escapeHtml(c.source) || '—'}</td>` +
      `<td class="mono">${escapeHtml(c.target)}</td>`;
    tbody.appendChild(tr);
  }
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
  const startHour = Math.floor(now.getTime() / 3600000) - hours + 1;
  const buckets = [];
  for (let h = startHour; h <= Math.floor(now.getTime() / 3600000); h++) {
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
  const W = el.clientWidth - 16;
  const H = 220 - 16;
  const bw = W / buckets.length;

  const svgNS = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('width', W);
  svg.setAttribute('height', H);

  for (let i = 0; i < buckets.length; i++) {
    const b = buckets[i];
    const total = b.up + b.down;
    const h = (total / max) * H;
    const x = i * bw;
    const y = H - h;
    if (b.up > 0) {
      const uh = (b.up / max) * H;
      const rect = document.createElementNS(svgNS, 'rect');
      rect.setAttribute('x', x + 1);
      rect.setAttribute('y', y);
      rect.setAttribute('width', Math.max(bw - 2, 1));
      rect.setAttribute('height', uh);
      rect.setAttribute('fill', '#38d39f');
      svg.appendChild(rect);
    }
    if (b.down > 0) {
      const dh = (b.down / max) * H;
      const rect = document.createElementNS(svgNS, 'rect');
      rect.setAttribute('x', x + 1);
      rect.setAttribute('y', y + (b.up / max) * H);
      rect.setAttribute('width', Math.max(bw - 2, 1));
      rect.setAttribute('height', dh);
      rect.setAttribute('fill', '#5aa2ff');
      svg.appendChild(rect);
    }
    const title = document.createElementNS(svgNS, 'title');
    title.textContent = `${fmtHourLabel(b.hour)}  上行 ${fmtBytes(b.up)}  下行 ${fmtBytes(b.down)}`;
    svg.appendChild(title);
  }

  const legend = document.createElement('div');
  legend.style.marginTop = '6px';
  legend.style.fontSize = '12px';
  legend.style.color = 'var(--muted)';
  legend.innerHTML = '<span style="color:#38d39f">■</span> 上行 &nbsp; <span style="color:#5aa2ff">■</span> 下行';
  el.appendChild(svg);
  el.appendChild(legend);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

async function bootstrap() {
  const ov = await fetchJSON('api/overview');
  buildUserSelect(ov.users);
  await refreshOverview();
  await refreshConnections();
  await refreshChart();
}

document.getElementById('chart-user').addEventListener('change', refreshChart);
document.getElementById('chart-hours').addEventListener('change', refreshChart);

setInterval(() => { refreshOverview().catch(() => {}); refreshConnections().catch(() => {}); }, 15000);

bootstrap().catch(() => {
  document.body.innerHTML = '<div style="padding:40px;text-align:center;color:#8a96a3">面板加载失败，请稍后重试</div>';
});
