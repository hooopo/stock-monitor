#!/usr/bin/env ruby
require "json"
require "yaml"
require "erubi"

PRICES_JSON = File.expand_path("../data/prices.json", __dir__)
INDEX_HTML = File.expand_path("../public/index.html", __dir__)
TEMPLATE_ERB = <<~ERB
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>股票监控 - 跌幅榜</title>
<style>
:root {
  --bg: #f4f6fb;
  --card: #ffffff;
  --text: #1f2937;
  --text-secondary: #6b7280;
  --text-muted: #9ca3af;
  --border: #e5e7eb;
  --accent: #3b82f6;
  --red: #dc2626;
  --red-soft: #fef2f2;
  --orange: #ea580c;
  --orange-soft: #fff7ed;
  --yellow: #ca8a04;
  --yellow-soft: #fefce8;
  --green: #059669;
  --green-soft: #ecfdf5;
  --blue-soft: #eff6ff;
  --row-below: #dcfce7;
  --row-below-sticky: #bbf7d0;
  --row-below-bar: #10b981;
  --row-near: #fee2e2;
  --row-near-sticky: #fecaca;
  --row-near-bar: #ef4444;
  --row-mid: #ffedd5;
  --row-mid-sticky: #fed7aa;
  --row-mid-bar: #f97316;
  --row-far: #ffffff;
  --row-far-sticky: #ffffff;
  --row-far-bar: #9ca3af;
  --shadow-sm: 0 1px 2px rgba(16,24,40,0.04), 0 1px 3px rgba(16,24,40,0.06);
  --shadow-md: 0 2px 8px rgba(16,24,40,0.06), 0 4px 16px rgba(16,24,40,0.04);
  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f172a;
    --card: #1e293b;
    --text: #f1f5f9;
    --text-secondary: #cbd5e1;
    --text-muted: #64748b;
    --border: #334155;
    --red-soft: #3f1d1d;
    --orange-soft: #3d2817;
    --yellow-soft: #3d3510;
    --green-soft: #0f3329;
    --blue-soft: #172554;
    --row-below: #14532d;
    --row-below-sticky: #14532d;
    --row-below-bar: #22c55e;
    --row-near: #450a0a;
    --row-near-sticky: #450a0a;
    --row-near-bar: #ef4444;
    --row-mid: #431407;
    --row-mid-sticky: #431407;
    --row-mid-bar: #f97316;
    --row-far: #1e293b;
    --row-far-sticky: #1e293b;
    --row-far-bar: #64748b;
    --shadow-sm: 0 1px 2px rgba(0,0,0,0.3), 0 1px 3px rgba(0,0,0,0.2);
    --shadow-md: 0 2px 8px rgba(0,0,0,0.3), 0 4px 16px rgba(0,0,0,0.2);
  }
}

* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }

html { -webkit-text-size-adjust: 100%; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
  background: var(--bg);
  color: var(--text);
  font-size: 14px;
  line-height: 1.5;
  min-height: 100vh;
  padding: 12px;
  transition: background 0.2s, color 0.2s;
}

.container {
  max-width: 480px;
  margin: 0 auto;
}

.header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border-radius: var(--radius-lg);
  padding: 18px 18px 16px;
  margin-bottom: 14px;
  box-shadow: 0 6px 20px rgba(102,126,234,0.35);
  position: relative;
  overflow: hidden;
}
.header::before {
  content: "";
  position: absolute;
  right: -20px; top: -20px;
  width: 100px; height: 100px;
  background: rgba(255,255,255,0.08);
  border-radius: 50%;
}
.header::after {
  content: "";
  position: absolute;
  right: 20px; bottom: -30px;
  width: 60px; height: 60px;
  background: rgba(255,255,255,0.06);
  border-radius: 50%;
}
.header h1 {
  font-size: 19px;
  font-weight: 700;
  margin-bottom: 4px;
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 6px;
}
.header .meta {
  font-size: 12px;
  color: rgba(255,255,255,0.85);
  position: relative;
  z-index: 1;
}

.stats {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin-bottom: 14px;
}
.stat-card {
  background: var(--card);
  border-radius: var(--radius-md);
  padding: 12px 8px;
  text-align: center;
  box-shadow: var(--shadow-sm);
  border: 1px solid var(--border);
  transition: transform 0.15s;
}
.stat-card:active { transform: scale(0.97); }
.stat-card .label {
  font-size: 11px;
  color: var(--text-secondary);
  margin-bottom: 5px;
  font-weight: 500;
}
.stat-card .value {
  font-size: 18px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.stat-card .value.red { color: var(--red); }
.stat-card .value.green { color: var(--green); }

.filter-bar {
  background: var(--card);
  border-radius: var(--radius-md);
  padding: 12px;
  margin-bottom: 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  box-shadow: var(--shadow-sm);
  border: 1px solid var(--border);
}
.filter-bar .row {
  display: flex;
  gap: 8px;
}
.filter-bar input, .filter-bar select {
  flex: 1;
  min-width: 0;
  padding: 9px 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  font-size: 13px;
  outline: none;
  background: var(--card);
  color: var(--text);
  transition: border-color 0.15s, box-shadow 0.15s;
  -webkit-appearance: none;
  appearance: none;
}
.filter-bar select {
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%239ca3af' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 10px center;
  padding-right: 30px;
}
.filter-bar input:focus, .filter-bar select:focus {
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(59,130,246,0.12);
}
.filter-bar .row select { flex: 1; }

.table-wrap {
  background: var(--card);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
  border: 1px solid var(--border);
}
table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  display: block;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
thead {
  background: var(--card);
  position: sticky;
  top: 0;
  z-index: 2;
  border-bottom: 1px solid var(--border);
}
th, td {
  padding: 10px 8px;
  text-align: right;
  white-space: nowrap;
  vertical-align: middle;
}
td { border-bottom: 1px solid var(--border); }
tr:last-child td { border-bottom: none; }
th:first-child, td:first-child {
  text-align: left;
  position: sticky;
  left: 0;
  background: inherit;
  z-index: 1;
}
thead th:first-child { z-index: 3; }
th {
  font-size: 11px;
  color: var(--text-secondary);
  font-weight: 600;
  cursor: pointer;
  user-select: none;
  letter-spacing: 0.2px;
  transition: background 0.15s;
}
th:hover { background: var(--bg); }
th.sorted { color: var(--accent); }
tbody tr { transition: background 0.1s; }
tbody tr td { border-left: 3px solid transparent; }
tbody tr.row-below { background: var(--row-below); }
tbody tr.row-below td:first-child { border-left-color: var(--row-below-bar); }
tbody tr.row-near  { background: var(--row-near); }
tbody tr.row-near td:first-child  { border-left-color: var(--row-near-bar); }
tbody tr.row-mid   { background: var(--row-mid); }
tbody tr.row-mid td:first-child   { border-left-color: var(--row-mid-bar); }
tbody tr.row-far   { background: var(--row-far); }
tbody tr.row-far td:first-child   { border-left-color: var(--row-far-bar); }
tbody tr.row-below td:first-child,
tbody tr.row-below th:first-child { background: var(--row-below-sticky); }
tbody tr.row-near td:first-child,
tbody tr.row-near th:first-child  { background: var(--row-near-sticky); }
tbody tr.row-mid td:first-child,
tbody tr.row-mid th:first-child   { background: var(--row-mid-sticky); }
tbody tr.row-far td:first-child,
tbody tr.row-far th:first-child   { background: var(--row-far-sticky); }
tbody tr:active { filter: brightness(0.95); }
tr.hidden { display: none; }

.stock-cell { min-width: 90px; }
.name {
  font-weight: 600;
  color: var(--text);
  font-size: 14px;
  line-height: 1.2;
}
.code {
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 2px;
  font-family: "SF Mono", ui-monospace, Menlo, monospace;
}
.cat {
  font-size: 11px;
  color: var(--text-secondary);
  display: inline-block;
  padding: 2px 6px;
  background: var(--bg);
  border-radius: 4px;
  font-weight: 500;
}
.num {
  font-variant-numeric: tabular-nums;
  font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace;
  font-size: 13px;
}
.neg { color: var(--red); }
.pos { color: var(--green); }

.roe-high { color: var(--green); font-weight: 600; }
.roe-mid { color: var(--text-secondary); }
.roe-low { color: var(--red); }

.drop-visual {
  display: block;
  margin-top: 4px;
  height: 5px;
  background: var(--border);
  border-radius: 3px;
  overflow: hidden;
  min-width: 60px;
}
.drop-visual .bar {
  height: 100%;
  border-radius: 3px;
  transition: width 0.3s;
}
.drop-visual .bar.green { background: linear-gradient(90deg, #059669, #10b981); }
.drop-visual .bar.orange { background: linear-gradient(90deg, #ea580c, #f97316); }
.drop-visual .bar.red { background: linear-gradient(90deg, #dc2626, #ef4444); }

.legend {
  background: var(--card);
  border-radius: var(--radius-md);
  padding: 10px 12px;
  margin-bottom: 12px;
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 6px 10px;
  box-shadow: var(--shadow-sm);
  border: 1px solid var(--border);
}
.legend-item {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 11px;
  color: var(--text-secondary);
}
.legend-bar {
  width: 16px;
  height: 14px;
  border-radius: 3px;
  border-left: 3px solid;
  flex-shrink: 0;
}
.legend-bar.below { background: var(--row-below); border-left-color: var(--row-below-bar); }
.legend-bar.near  { background: var(--row-near);  border-left-color: var(--row-near-bar); }
.legend-bar.mid   { background: var(--row-mid);   border-left-color: var(--row-mid-bar); }
.legend-bar.far   { background: var(--row-far);   border-left-color: var(--row-far-bar); border: 1px solid var(--border); border-left-width: 3px; }

@media (min-width: 768px) {
  .legend {
    grid-template-columns: repeat(4, 1fr);
    gap: 8px 16px;
    padding: 12px 16px;
    margin-bottom: 16px;
  }
  .legend-item { font-size: 12px; }

  body { padding: 28px 20px; font-size: 14px; }
  .container { max-width: 1100px; }
  .header { padding: 26px 28px; margin-bottom: 20px; }
  .header h1 { font-size: 24px; }
  .header .meta { font-size: 13px; }
  .stats {
    grid-template-columns: repeat(6, 1fr);
    gap: 12px;
    margin-bottom: 20px;
  }
  .stat-card { padding: 18px 12px; border-radius: var(--radius-md); }
  .stat-card:hover { transform: translateY(-2px); box-shadow: var(--shadow-md); }
  .stat-card .label { font-size: 12px; margin-bottom: 8px; }
  .stat-card .value { font-size: 22px; }
  .filter-bar {
    flex-direction: row;
    align-items: center;
    padding: 14px;
    margin-bottom: 20px;
  }
  .filter-bar .row { flex: 2; }
  .filter-bar input { flex: 1.5; }
  table { display: table; }
  th, td { padding: 13px 14px; }
  th { font-size: 12px; }
  tbody tr:hover { filter: brightness(0.97); }
  tbody tr:active { filter: none; }
  .stock-cell { min-width: 160px; }
  .name { font-size: 15px; }
  .num { font-size: 14px; }
  .drop-visual { min-width: 100px; margin-top: 5px; }
}

@media (min-width: 1280px) {
  .container { max-width: 1280px; }
  .stats { grid-template-columns: repeat(6, 1fr); }
  th, td { padding: 14px 18px; }
}
</style>
</head>
<body>
<div class="container">
<div class="header">
  <h1>📈 股票监控榜</h1>
  <div class="meta">更新时间: <%= generated_at %> &nbsp;·&nbsp; 共 <%= stocks.size %> 只股票</div>
</div>

<div class="stats">
  <div class="stat-card">
    <div class="label">已跌破买入价</div>
    <div class="value red"><%= stats[:below_count] %></div>
  </div>
  <div class="stat-card">
    <div class="label">需跌0-5%</div>
    <div class="value"><%= stats[:near_count] %></div>
  </div>
  <div class="stat-card">
    <div class="label">需跌5-10%</div>
    <div class="value"><%= stats[:mid_count] %></div>
  </div>
  <div class="stat-card">
    <div class="label">需跌>10%</div>
    <div class="value"><%= stats[:far_count] %></div>
  </div>
  <div class="stat-card">
    <div class="label">平均需跌幅</div>
    <div class="value"><%= stats[:avg_drop] %>%</div>
  </div>
  <div class="stat-card">
    <div class="label">平均ROE</div>
    <div class="value green"><%= stats[:avg_roe] %>%</div>
  </div>
</div>

<div class="filter-bar">
  <input type="text" id="searchInput" placeholder="🔍 搜索名称/代码/分类...">
  <div class="row">
    <select id="categoryFilter">
      <option value="">全部分类</option>
      <% categories.each do |c| %>
      <option value="<%= c %>"><%= c %></option>
      <% end %>
    </select>
    <select id="dropFilter">
      <option value="">全部跌幅</option>
      <option value="below">已跌破买入价</option>
      <option value="0-5">需跌0-5%</option>
      <option value="5-10">需跌5-10%</option>
      <option value="10+">需跌10%以上</option>
    </select>
  </div>
</div>

<div class="legend">
  <div class="legend-item"><span class="legend-bar below"></span>已跌破买入价</div>
  <div class="legend-item"><span class="legend-bar near"></span>需跌 0–5%（接近）</div>
  <div class="legend-item"><span class="legend-bar mid"></span>需跌 5–10%（中等）</div>
  <div class="legend-item"><span class="legend-bar far"></span>需跌 ≥10%（较远）</div>
</div>

<div class="table-wrap">
<table id="stockTable">
<thead>
<tr>
  <th data-sort="name">股票</th>
  <th data-sort="category">分类</th>
  <th data-sort="buy_price">首仓价</th>
  <th data-sort="current_price">现价</th>
  <th data-sort="need_drop" class="sorted-asc">需跌幅 ↓</th>
  <th data-sort="roe">ROE%</th>
</tr>
</thead>
<tbody>
<% stocks.each_with_index do |s, i| %>
<%
  nd = s['need_drop_pct'].round(2)
  nd_abs = [nd.abs, 30].min
  nd_pct = (nd_abs / 30.0 * 100).round(1)
  if nd < 0
    bar_color = 'green'
    row_class = 'row-below'
  elsif nd < 5
    bar_color = 'red'
    row_class = 'row-near'
  elsif nd < 10
    bar_color = 'orange'
    row_class = 'row-mid'
  else
    bar_color = 'orange'
    row_class = 'row-far'
  end
  r = s['roe'] ? s['roe'].round(2) : nil
%>
<tr
  class="<%= row_class %>"
  data-name="<%= s['name'] %> <%= s['code'] %>"
  data-category="<%= s['category'] %>"
  data-drop="<%= nd %>"
>
  <td class="stock-cell">
    <div class="name"><%= s['name'] %></div>
    <div class="code"><%= s['code'] %></div>
  </td>
  <td><span class="cat"><%= s['category'] %></span></td>
  <td class="num"><%= '%.2f' % s['buy_price'] %></td>
  <td class="num"><%= '%.2f' % s['current_price'] %></td>
  <td class="num">
    <span class="<%= nd < 0 ? 'neg' : 'pos' %>">
      <%= nd > 0 ? '+' : '' %><%= '%.2f' % nd %>%
    </span>
    <span class="drop-visual"><span class="bar <%= bar_color %>" style="width:<%= nd_pct %>%"></span></span>
  </td>
  <td class="num">
    <% if r %>
      <span class="<%= r >= 10 ? 'roe-high' : r >= 5 ? 'roe-mid' : 'roe-low' %>">
        <%= '%.2f' % r %>%
      </span>
    <% else %>
      <span style="color:var(--text-muted)">—</span>
    <% end %>
  </td>
</tr>
<% end %>
</tbody>
</table>
</div>
</div>

<script>
(function() {
  const searchInput = document.getElementById('searchInput');
  const categoryFilter = document.getElementById('categoryFilter');
  const dropFilter = document.getElementById('dropFilter');
  const rows = document.querySelectorAll('#stockTable tbody tr');
  const headers = document.querySelectorAll('#stockTable th');

  let currentSort = { key: 'need_drop', dir: 'asc' };

  function applyFilters() {
    const q = searchInput.value.trim().toLowerCase();
    const cat = categoryFilter.value;
    const drop = dropFilter.value;

    rows.forEach(row => {
      const name = row.dataset.name.toLowerCase();
      const category = row.dataset.category;
      const nd = parseFloat(row.dataset.drop);

      let ok = true;
      if (q && !name.includes(q) && !category.toLowerCase().includes(q)) ok = false;
      if (cat && category !== cat) ok = false;
      if (drop === 'below' && nd >= 0) ok = false;
      if (drop === '0-5' && !(nd >= 0 && nd < 5)) ok = false;
      if (drop === '5-10' && !(nd >= 5 && nd < 10)) ok = false;
      if (drop === '10+' && nd < 10) ok = false;

      row.classList.toggle('hidden', !ok);
    });
  }

  function getCellValue(row, key) {
    const cells = row.children;
    switch(key) {
      case 'name': return row.dataset.name;
      case 'category': return row.dataset.category;
      case 'buy_price': return parseFloat(cells[2].textContent);
      case 'current_price': return parseFloat(cells[3].textContent);
      case 'need_drop': return parseFloat(row.dataset.drop);
      case 'roe':
        const r = cells[5].textContent.trim();
        return r === '—' ? -999 : parseFloat(r);
    }
  }

  function sortTable() {
    const tbody = document.querySelector('#stockTable tbody');
    const arr = Array.from(rows);
    arr.sort((a, b) => {
      let va = getCellValue(a, currentSort.key);
      let vb = getCellValue(b, currentSort.key);
      if (typeof va === 'string') return currentSort.dir === 'asc' ? va.localeCompare(vb) : vb.localeCompare(va);
      return currentSort.dir === 'asc' ? va - vb : vb - va;
    });
    arr.forEach(r => tbody.appendChild(r));

    headers.forEach(h => {
      h.textContent = h.textContent.replace(/ [↓↑]$/, '');
      if (h.dataset.sort === currentSort.key) {
        h.textContent += currentSort.dir === 'asc' ? ' ↓' : ' ↑';
        h.classList.add('sorted');
      }
    });
  }

  searchInput.addEventListener('input', applyFilters);
  categoryFilter.addEventListener('change', applyFilters);
  dropFilter.addEventListener('change', applyFilters);

  headers.forEach(h => {
    h.addEventListener('click', () => {
      const key = h.dataset.sort;
      if (currentSort.key === key) {
        currentSort.dir = currentSort.dir === 'asc' ? 'desc' : 'asc';
      } else {
        currentSort.key = key;
        currentSort.dir = key === 'need_drop' ? 'asc' : 'desc';
      }
      sortTable();
    });
  });

  sortTable();
})();
</script>
</body>
</html>
ERB

def load_data
  data = if File.exist?(PRICES_JSON)
           JSON.parse(File.read(PRICES_JSON))
         else
           YAML.load_file(PRICES_JSON.sub("prices.json", "stocks.yml"))
         end
  data
end

def process(stocks)
  stocks.each do |s|
    cur = s["current_price"] || s["reference_price"]
    buy = s["buy_price"]
    s["current_price"] = cur
    s["need_drop_pct"] = if buy > 0
                           (cur - buy) / buy * 100.0
                         else
                           0.0
                         end
  end

  stocks.sort_by! { |s| s["need_drop_pct"] }
end

def calc_stats(stocks)
  below = stocks.count { |s| s["current_price"] < s["buy_price"] }
  near = stocks.count { |s| s["need_drop_pct"] >= 0 && s["need_drop_pct"] < 5 }
  mid = stocks.count { |s| s["need_drop_pct"] >= 5 && s["need_drop_pct"] < 10 }
  far = stocks.count { |s| s["need_drop_pct"] >= 10 }
  roes = stocks.map { |s| s["roe"] }.compact
  drops = stocks.map { |s| s["need_drop_pct"] }

  avg_roe = roes.empty? ? 0.0 : roes.sum / roes.size
  avg_drop = drops.empty? ? 0.0 : drops.sum / drops.size

  {
    below_count: below,
    near_count: near,
    mid_count: mid,
    far_count: far,
    avg_roe: "%.2f" % avg_roe,
    avg_drop: "%.2f" % avg_drop
  }
end

stocks = load_data
process(stocks)
stats = calc_stats(stocks)
categories = stocks.map { |s| s["category"] }.uniq.sort
generated_at = Time.now.strftime("%Y-%m-%d %H:%M:%S")

template = Erubi::Engine.new(TEMPLATE_ERB, escape: true)
html = eval(template.src)
File.write(INDEX_HTML, html)
puts "页面已生成: #{INDEX_HTML}"
puts "统计: 跌破#{stats[:below_count]}只 | 平均需跌#{stats[:avg_drop]}% | 平均ROE#{stats[:avg_roe]}%"
