#!/usr/bin/env ruby
require "json"
require "yaml"
require "erubi"
require "faraday"

STOCKS_YAML = File.expand_path("../data/stocks.yml", __dir__)
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

.chk {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 0 10px;
  min-height: 38px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
  background: var(--card);
  color: var(--text);
  font-size: 13px;
  cursor: pointer;
  user-select: none;
  white-space: nowrap;
  transition: all 0.15s;
}
.chk:hover { border-color: var(--accent); }
.chk-box {
  width: 16px;
  height: 16px;
  border-radius: 4px;
  border: 1.5px solid #9ca3af;
  background: var(--card);
  position: relative;
  display: inline-block;
  transition: all 0.15s;
  flex-shrink: 0;
}
.chk-box.on {
  background: var(--accent);
  border-color: var(--accent);
}
.chk-box.on::after {
  content: "";
  position: absolute;
  left: 4px;
  top: 1px;
  width: 4px;
  height: 8px;
  border: solid #fff;
  border-width: 0 2px 2px 0;
  transform: rotate(45deg);
}

.refresh-btn {
  padding: 0 14px;
  min-height: 38px;
  border: 1px solid var(--accent);
  border-radius: var(--radius-sm);
  background: var(--accent);
  color: #fff;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: opacity 0.15s, transform 0.05s;
  flex-shrink: 0;
}
.refresh-btn:hover { filter: brightness(1.05); }
.refresh-btn:active { transform: translateY(1px); }
.refresh-btn:disabled { opacity: 0.6; cursor: wait; filter: grayscale(0.3); }
.refresh-btn.done { background: #16a34a; border-color: #16a34a; }

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
.satellite-badge {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  font-size: 10px;
  font-weight: 600;
  color: #6d28d9;
  background: #ede9fe;
  padding: 1px 5px;
  border-radius: 4px;
  margin-left: 4px;
  line-height: 1.4;
  vertical-align: middle;
}
@media (prefers-color-scheme: dark) {
  .satellite-badge {
    color: #c4b5fd;
    background: #3b2a66;
  }
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

.disclaimer {
  margin-top: 16px;
  background: var(--card);
  border-radius: var(--radius-md);
  padding: 14px 16px;
  box-shadow: var(--shadow-sm);
  border: 1px solid var(--border);
  border-left: 4px solid var(--yellow);
}
.disclaimer-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--text);
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.disclaimer p {
  font-size: 12px;
  line-height: 1.7;
  color: var(--text-secondary);
  margin-bottom: 6px;
}
.disclaimer p:last-child { margin-bottom: 0; }
.disclaimer strong {
  color: var(--text);
  font-weight: 600;
}

@media (min-width: 768px) {
  .disclaimer {
    margin-top: 24px;
    padding: 18px 22px;
    border-left-width: 5px;
  }
  .disclaimer-title { font-size: 14px; margin-bottom: 10px; }
  .disclaimer p { font-size: 13px; line-height: 1.8; margin-bottom: 8px; }
}
</style>
</head>
<body>
<div class="container">
<div class="header">
  <h1>📈 股票监控榜</h1>
  <div class="meta">
    <span id="updateTime">更新时间: <%= generated_at %></span>
    &nbsp;·&nbsp;
    共 <%= stocks.size %> 只股票
  </div>
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
    <button id="refreshBtn" class="refresh-btn">🔄 刷新现价</button>
    <label class="chk">
      <input type="checkbox" id="showHK" style="display:none">
      <span class="chk-box" id="hkBox"></span>
      <span id="hkLabel">显示港股</span>
    </label>
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
  cur = s['current_price']
  nd = cur && !s['need_drop_pct'].infinite? ? s['need_drop_pct'].round(2) : nil
  if nd.nil?
    nd_abs = 0
    nd_pct = 0
    bar_color = 'orange'
    row_class = 'row-far'
    nd_txt = '—'
  else
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
  end
  r = s['roe'] ? s['roe'].round(2) : nil
%>
<tr
  class="<%= row_class %> stock-row"
  data-market="<%= s['code'].end_with?('.HK') ? 'HK' : 'A' %>"
  data-code="<%= s['code'] %>"
  data-buy="<%= s['buy_price'] %>"
  data-name="<%= s['name'] %> <%= s['code'] %>"
  data-category="<%= s['category'] %>"
  data-drop="<%= nd ? nd : 999999 %>"
  data-satellite="<%= s['satellite'] ? '1' : '0' %>"
>
  <td class="stock-cell">
    <div class="name"><%= s['name'] %><% if s['satellite'] %><span class="satellite-badge" title="卫星仓（高波动/成长风格，非核心红利持仓）">🛰 卫星</span><% end %></div>
    <div class="code"><%= s['code'] %></div>
  </td>
  <td><span class="cat"><%= s['category'] %></span></td>
  <td class="num"><%= '%.2f' % s['buy_price'] %></td>
  <td class="num"><% if cur %><%= '%.2f' % cur %><% else %><span class="muted">—</span><% end %></td>
  <td class="num">
    <% if nd %>
    <span class="<%= nd < 0 ? 'neg' : 'pos' %>">
      <%= nd > 0 ? '+' : '' %><%= '%.2f' % nd %>%
    </span>
    <% else %>
    <span class="muted">—</span>
    <% end %>
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

<div class="disclaimer">
  <div class="disclaimer-title">⚠️ 重要提示与免责声明</div>
  <p><strong>不构成投资建议：</strong>本页面所有内容仅为个人投资记录与研究整理，不构成任何买入或卖出的投资建议、不提供任何收益承诺。股市有风险，入市需谨慎，决策前请独立思考并自行承担风险。</p>
  <p><strong>不预测短期走势：</strong>价格、ROE 等数据来源于公开网络（新浪行情、东方财富），仅作客观展示，不对任何短期（日/周/月级）涨跌作预测或判断。</p>
  <p><strong>关于"首仓价"：</strong>表中 <strong>首仓价</strong> 为个人建仓时的折中参考价——综合考虑 <strong>估值安全边际</strong>（如 PB/PE/股息率/ROE 等）与实际市场中 <strong>能够成交买入的价格区间</strong> 两方面因素后给出的<strong>大致估算值</strong>，既非最低点、也非严格的买卖指令，仅作长期价值建仓的心理锚定参考。</p>
  <p><strong>数据准确性：</strong>行情与财务数据来自第三方接口，可能存在延迟、缺失或错误，请以交易所和上市公司正式公告为准。页面按工作日定时自动更新，手动触发亦可。</p>
</div>
</div>

<script>
(function() {
  // ============================================================
  //  Cloudflare Workers Proxy (REQUIRED for GitHub Pages mode)
  // ============================================================
  //  After you run `npx wrangler@latest deploy` in this repo,
  //  replace the string below with your real workers.dev URL
  //  (no trailing slash), e.g.  "https://stock-quote-proxy.foo.workers.dev"
  //
  //  If you leave it empty (""), GitHub Pages mode will try the
  //  built-in qt.gtimg.cn direct path as a fallback.
  //
  //  Also overrideable per-page load in DevTools console:
  //    window.STOCK_PROXY_BASE = "https://YOUR.workers.dev";
  const DEFAULT_PROXY_BASE = "https://stock-quote-proxy.hooopo.workers.dev";

  const searchInput = document.getElementById('searchInput');
  const categoryFilter = document.getElementById('categoryFilter');
  const dropFilter = document.getElementById('dropFilter');
  const showHk = document.getElementById('showHK');
  const hkBox = document.getElementById('hkBox');
  const hkLabel = document.getElementById('hkLabel');
  const refreshBtn = document.getElementById('refreshBtn');
  const updateTimeEl = document.getElementById('updateTime');
  const rows = Array.from(document.querySelectorAll('#stockTable tbody tr'));
  const headers = document.querySelectorAll('#stockTable th');

  let currentSort = { key: 'need_drop', dir: 'asc' };

  function applyFilters() {
    const q = searchInput.value.trim().toLowerCase();
    const cat = categoryFilter.value;
    const drop = dropFilter.value;
    const includeHK = showHk.checked;

    rows.forEach(row => {
      const name = row.dataset.name.toLowerCase();
      const category = row.dataset.category;
      const nd = parseFloat(row.dataset.drop);
      const market = row.dataset.market || 'A';

      let ok = true;
      if (market === 'HK' && !includeHK) ok = false;
      if (q && !name.includes(q) && !category.toLowerCase().includes(q)) ok = false;
      if (cat && category !== cat) ok = false;
      if (drop === 'below' && nd >= 0) ok = false;
      if (drop === '0-5' && !(nd >= 0 && nd < 5)) ok = false;
      if (drop === '5-10' && !(nd >= 5 && nd < 10)) ok = false;
      if (drop === '10+' && nd < 10) ok = false;

      row.classList.toggle('hidden', !ok);
    });
  }

  function toggleHkVisual(on) {
    hkBox.classList.toggle('on', !!on);
    hkLabel.textContent = on ? '显示全部 (A+H)' : '只显示 A股';
  }

  showHk.addEventListener('change', function() {
    toggleHkVisual(showHk.checked);
    try { localStorage.setItem('showHK', showHk.checked ? '1' : '0'); } catch(e) {}
    applyFilters();
  });
  hkBox.addEventListener('click', function(e) {
    e.preventDefault();
    showHk.checked = !showHk.checked;
    showHk.dispatchEvent(new Event('change'));
  });
  hkLabel.addEventListener('click', function(e) {
    e.preventDefault();
    showHk.checked = !showHk.checked;
    showHk.dispatchEvent(new Event('change'));
  });

  try {
    const saved = localStorage.getItem('showHK');
    if (saved === '1') showHk.checked = true;
  } catch(e) {}
  toggleHkVisual(showHk.checked);

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

  function fmtPrice(p) { return (Math.round(p * 100) / 100).toFixed(2); }

  function updateRowPrice(row, curPrice) {
    if (!curPrice || curPrice <= 0) return false;
    const cells = row.children;
    const buy = parseFloat(row.dataset.buy);
    cells[3].innerHTML = fmtPrice(curPrice);
    const nd = ((curPrice - buy) / curPrice) * 100;
    const ndRounded = Math.round(nd * 100) / 100;
    const nd_abs = Math.min(Math.abs(ndRounded), 30);
    const nd_pct = Math.round(nd_abs / 30.0 * 1000) / 10;

    let bar_color = 'orange', row_class = 'row-far';
    if (ndRounded < 0) { bar_color = 'green'; row_class = 'row-below'; }
    else if (ndRounded < 5) { bar_color = 'red'; row_class = 'row-near'; }
    else if (ndRounded < 10) { bar_color = 'orange'; row_class = 'row-mid'; }
    else { bar_color = 'orange'; row_class = 'row-far'; }

    row.className = row_class + ' stock-row';
    row.dataset.drop = ndRounded;

    const sign = ndRounded > 0 ? '+' : '';
    const cls = ndRounded < 0 ? 'neg' : 'pos';
    cells[4].innerHTML =
      '<span class="' + cls + '">' + sign + ndRounded.toFixed(2) + '%</span>' +
      '<div class="progress"><div class="bar ' + bar_color + '" style="width:' + nd_pct + '%"></div></div>';
    return true;
  }

  function codeToSina(code) {
    const parts = code.split(".");
    const num = parts[0];
    const mkt = parts[1];
    if (mkt === "SH") return "sh" + num;
    if (mkt === "SZ") return "sz" + num;
    if (mkt === "HK") return "hk" + num;
    return "";
  }

  function codeToQQ(code) {
    const parts = code.split(".");
    const num = parts[0];
    const mkt = parts[1];
    if (mkt === "SH") return "sh" + num;
    if (mkt === "SZ") return "sz" + num;
    if (mkt === "HK") return "r_hk" + num;
    return "";
  }

  function mockPriceFor(row) {
    const buy = parseFloat(row.dataset.buy) || 10;
    const fixedJitter = (Math.abs(
      Array.from(row.dataset.code || "").reduce(function(a, c) { return a * 131 + c.charCodeAt(0); }, 7)
    ) % 1000) / 1000.0;
    const scenarios = [-0.22, -0.08, -0.03, 0.02, 0.06, 0.12, 0.25, 0.55];
    const s = scenarios[Math.floor(fixedJitter * scenarios.length)];
    return Math.max(0.01, buy * (1.0 + s));
  }

  function resolveProxyBase() {
    const WS = String.fromCharCode(47);
    const lastSlash = function(s) { while (s.length > 0 && s.charAt(s.length - 1) === WS) { s = s.substring(0, s.length - 1); } return s; };
    if (typeof window.STOCK_PROXY_BASE === "string" && window.STOCK_PROXY_BASE.length > 0) {
      return lastSlash(window.STOCK_PROXY_BASE);
    }
    if (typeof DEFAULT_PROXY_BASE === "string" && DEFAULT_PROXY_BASE.length > 0) {
      return lastSlash(DEFAULT_PROXY_BASE);
    }
    return "";
  }

  function proxyBatchFetch(codes) {
    // Worker endpoint: GET ${proxyBase}/?list=sh,sz,r_hk  -> JSON { qq_key: price }
    return new Promise(function(resolve) {
      const base = resolveProxyBase();
      if (!base) { resolve({}); return; }
      const qqList = codes.map(codeToQQ).filter(function(x){ return x && x.length > 0; }).join(",");
      if (!qqList) { resolve({}); return; }
      const url = base + "/?list=" + encodeURIComponent(qqList) + "&_t=" + Date.now();
      const xhr = new XMLHttpRequest();
      let settled = false;
      const finish = function(obj) {
        if (settled) return;
        settled = true;
        // Worker returns JSON with QQ-style keys (shNNNNNN / szNNNNNN / r_hkNNNNN).
        // Downstream consumers want Sina-style keys (shNNNNNN / szNNNNNN / hkNNNNN).
        const out = {};
        codes.forEach(function(code) {
          const qq = codeToQQ(code);
          const sc = codeToSina(code);
          const p = obj && obj[qq];
          if (typeof p === "number" && p > 0) out[sc] = p;
        });
        resolve(out);
      };
      xhr.open("GET", url, true);
      xhr.timeout = 15000;
      xhr.responseType = "json";
      xhr.onload = function() {
        try {
          const body = (typeof xhr.response === "object" && xhr.response !== null) ? xhr.response : {};
          finish(body || {});
        } catch(e) { finish({}); }
      };
      xhr.onerror = function() { finish({}); };
      xhr.ontimeout = function() { finish({}); };
      try { xhr.send(null); } catch(e) { finish({}); }
    });
  }

  function sinaBatchFetch(sinaCodes) {
    return new Promise(function(resolve) {
      const list = sinaCodes.join(",");
      const script = document.createElement("script");
      const stamp = Date.now() + "_" + Math.floor(Math.random() * 1e6);
      script.src = "/api/sina?list=" + encodeURIComponent(list) + "&rn=" + stamp;
      script.onerror = function() {
        try { document.head.removeChild(script); } catch(e) {}
        resolve({});
      };
      const done = function() {
        try { document.head.removeChild(script); } catch(e) {}
        const out = {};
        sinaCodes.forEach(function(sc) {
          const key = "hq_str_" + sc;
          if (typeof window[key] === "string" && window[key].length > 0) {
            try {
              const fields = window[key].split("~");
              let price = 0;
              if (sc.startsWith("hk")) {
                price = parseFloat(fields[6] || fields[2] || "0");
              } else {
                price = parseFloat(fields[3] || "0");
              }
              if (price > 0) out[sc] = price;
              try { delete window[key]; } catch(e) { window[key] = undefined; }
            } catch(e) {}
          }
        });
        resolve(out);
      };
      script.onload = done;
      setTimeout(done, 8000);
      document.head.appendChild(script);
    });
  }

  function qqBatchFetch(codes) {
    return new Promise(function(resolve) {
      const qqList = codes.map(codeToQQ).filter(function(x){ return x; }).join(",");
      if (!qqList) { resolve({}); return; }
      const url = "https://qt.gtimg.cn/q=" + encodeURIComponent(qqList);
      const xhr = new XMLHttpRequest();
      let settled = false;
      const finish = function(result) {
        if (settled) return;
        settled = true;
        const out = {};
        codes.forEach(function(code, i) {
          const qq = codeToQQ(code);
          const p = result[qq];
          if (p && p > 0) {
            const sc = codeToSina(code);
            out[sc] = p;
          }
        });
        resolve(out);
      };
      xhr.open("GET", url, true);
      xhr.timeout = 12000;
      xhr.responseType = "arraybuffer";
      xhr.onload = function() {
        if (settled) return;
        const raw = xhr.response;
        if (!raw || raw.byteLength === 0) { finish({}); return; }
        let text = "";
        try { text = new TextDecoder("gbk").decode(new Uint8Array(raw)); }
        catch(e) {
          try { text = new TextDecoder("utf-8", {fatal:false}).decode(new Uint8Array(raw)); }
          catch(e2) { finish({}); return; }
        }
        const result = {};
        const sep = new RegExp(String.fromCharCode(10) + "|;", "g");
        const lines = text.split(sep);
        lines.forEach(function(line) {
          const QU = String.fromCharCode(34);
          const re = new RegExp("v_(r_hk[0-9]+|[sh]z[0-9]+)=" + QU + "([^" + QU + "]*)" + QU);
          const m = line.match(re);
          if (!m) return;
          const key = m[1];
          const fields = m[2].split("~");
          const p = parseFloat(fields[3] || "0");
          if (p > 0) result[key] = p;
        });
        finish(result);
      };
      xhr.ontimeout = function() { finish({}); };
      xhr.onerror = function() { finish({}); };
      try { xhr.send(null); }
      catch(e) { finish({}); }
    });
  }

  async function refreshPrices() {
    if (refreshBtn.disabled) return;
    refreshBtn.disabled = true;
    const origText = refreshBtn.textContent;
    refreshBtn.classList.remove("done");

    const rowMap = {};
    rows.forEach(function(r) { rowMap[r.dataset.code] = r; });
    const pairs = rows.map(function(r){ return [codeToSina(r.dataset.code), r.dataset.code]; }).filter(function(x){ return x[0]; });
    const codeMap = {}; pairs.forEach(function(p) { codeMap[p[0]] = p[1]; });
    const codeList = pairs.map(function(p) { return p[1]; });
    const sinaList = pairs.map(function(p) { return p[0]; });
    const BATCH = 50;
    const batches = [];
    for (let i = 0; i < sinaList.length; i += BATCH) batches.push({ sina: sinaList.slice(i, i + BATCH), codes: codeList.slice(i, i + BATCH) });

    let okCount = 0;
    try {
      for (let i = 0; i < batches.length; i++) {
        refreshBtn.textContent = "刷新中 " + (i + 1) + "/" + batches.length + " ...";
        const batch = batches[i];
        let res;
        if (window.STOCK_MOCK_REFRESH === true) {
          const rr = {};
          batch.codes.forEach(function(code) {
            const sc = codeToSina(code);
            const row = rowMap[code];
            if (row) rr[sc] = mockPriceFor(row);
          });
          await new Promise(function(r){ setTimeout(function(){ r(); }, 400); });
          res = rr;
        } else {
          // Priority order:
          //   (A) local-like host + NOT github.io -> try local server.rb /api/sina first
          //       if <50% coverage, merge qq direct
          //   (B) github.io or STOCK_FORCE_DIRECT
          //       (B1) if Cloudflare proxy configured -> proxyBatchFetch
          //       (B2) if proxy 0 hits (or proxy not configured at all) -> qqBatchFetch fallback
          const isLocalLike = location.protocol.indexOf("http") === 0 &&
            location.hostname &&
            location.hostname.toLowerCase().indexOf("github.io") === -1;
          if (window.STOCK_FORCE_DIRECT === true || !isLocalLike) {
            // GitHub Pages / forced direct branch
            const base = resolveProxyBase();
            if (base.length > 0) {
              // (B1) Cloudflare proxy
              const proxied = await proxyBatchFetch(batch.codes);
              const got = Object.keys(proxied).length;
              if (got >= Math.max(1, Math.floor(batch.codes.length * 0.5))) {
                res = proxied;
              } else {
                const qq = await qqBatchFetch(batch.codes);
                res = Object.assign({}, proxied, qq);
              }
            } else {
              // (B2) no proxy configured -> direct qt.gtimg.cn CORS fallback
              res = await qqBatchFetch(batch.codes);
            }
          } else {
            // (A) local server branch
            const local = await sinaBatchFetch(batch.sina);
            const got = Object.keys(local).length;
            const need = batch.sina.length;
            if (got >= Math.max(1, Math.floor(need * 0.5))) {
              res = local;
            } else {
              const base = resolveProxyBase();
              if (base.length > 0) {
                const proxied = await proxyBatchFetch(batch.codes);
                res = Object.assign({}, local, proxied);
              }
              if (!res || Object.keys(res || {}).length < Math.max(1, Math.floor(need * 0.5))) {
                const qq = await qqBatchFetch(batch.codes);
                res = Object.assign({}, local || {}, res || {}, qq);
              }
            }
          }
        }
        Object.keys(res).forEach(function(sc) {
          const code = codeMap[sc];
          const row = rowMap[code];
          if (row && updateRowPrice(row, res[sc])) okCount++;
        });
        if (i < batches.length - 1) await new Promise(function(r){ setTimeout(function(){ r(); }, 300); });
      }
    } catch(e) {}

    sortTable();
    applyFilters();

    const now = new Date();
    const pad = function(n) { return String(n).padStart(2, "0"); };
    const tz = -now.getTimezoneOffset() / 60;
    const tzStr = (tz >= 0 ? "+" : "") + tz + ":00";
    updateTimeEl.textContent = "更新时间: " +
      now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate()) + " " +
      pad(now.getHours()) + ":" + pad(now.getMinutes()) + ":" + pad(now.getSeconds()) +
      " (UTC" + tzStr + ") · 前端已刷新 " + okCount + "/" + rows.length;
    refreshBtn.classList.add("done");
    refreshBtn.textContent = "✅ 刷新完成 " + okCount + "/" + rows.length;
    window.__LAST_REFRESH = { okCount: okCount, total: rows.length, time: Date.now() };
    setTimeout(function() {
      refreshBtn.textContent = origText;
      refreshBtn.classList.remove("done");
      refreshBtn.disabled = false;
    }, 2500);
  }

  refreshBtn.addEventListener('click', refreshPrices);

  function sortTable() {
    const tbody = document.querySelector('#stockTable tbody');
    rows.sort((a, b) => {
      let va = getCellValue(a, currentSort.key);
      let vb = getCellValue(b, currentSort.key);
      if (typeof va === 'string') return currentSort.dir === 'asc' ? va.localeCompare(vb) : vb.localeCompare(va);
      return currentSort.dir === 'asc' ? va - vb : vb - va;
    });
    rows.forEach(r => tbody.appendChild(r));

    headers.forEach(h => {
      // Strip trailing arrow ↓/↑ if present (avoid regex literal to keep ERB output stable)
      let t = h.textContent;
      const LWS = String.fromCharCode(32);
      const lastSpace = t.lastIndexOf(LWS);
      if (lastSpace !== -1 && lastSpace === t.length - 2) {
        const last = t.charAt(t.length - 1);
        if (last === String.fromCharCode(8595) || last === String.fromCharCode(8593)) {
          t = t.substring(0, lastSpace);
        }
      }
      h.textContent = t;
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
  applyFilters();
})();
</script>
</body>
</html>
ERB

def sina_code(code)
  num, market = code.split(".")
  market.downcase + num
end

def fetch_realtime_prices(codes)
  conn = Faraday.new(url: "https://hq.sinajs.cn") do |f|
    f.headers["Referer"] = "https://finance.sina.com.cn"
    f.adapter Faraday.default_adapter
  end

  batch_size = 50
  results = {}

  codes.each_slice(batch_size) do |slice|
    sina_codes = slice.map { |c| sina_code(c) }.join(",")
    resp = conn.get("/list=#{sina_codes}")
    next unless resp.success?

    resp.body.force_encoding("GBK").encode("UTF-8").split("\n").each do |line|
      match = line.match(/var hq_str_(\w+)="(.*)";/)
      next unless match

      sc = match[1]
      fields = match[2].split(",")
      next if fields.empty?

      orig_code = slice.find { |c| sina_code(c) == sc }
      next unless orig_code

      price = if sc.start_with?("hk")
                fields[6].to_f
              else
                fields[3].to_f
              end
      name = fields[0]
      date_idx = sc.start_with?("hk") ? 18 : 30
      time_idx = sc.start_with?("hk") ? 19 : 31
      results[orig_code] = {
        "name" => name,
        "current_price" => price,
        "open" => sc.start_with?("hk") ? fields[2].to_f : fields[1].to_f,
        "prev_close" => sc.start_with?("hk") ? fields[3].to_f : fields[2].to_f,
        "high" => sc.start_with?("hk") ? fields[4].to_f : fields[4].to_f,
        "low" => sc.start_with?("hk") ? fields[5].to_f : fields[5].to_f,
        "volume" => fields[8].to_i,
        "amount" => fields[9].to_f,
        "date" => fields[date_idx],
        "time" => fields[time_idx]
      }
    end
    sleep 0.5
  end

  results
end

def fetch_roe_a_share(codes)
  results = {}
  conn = Faraday.new(url: "https://emweb.securities.eastmoney.com") do |f|
    f.adapter Faraday.default_adapter
    f.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"
    f.ssl[:verify] = false
    f.options[:timeout] = 10
    f.options[:open_timeout] = 6
  end

  codes.each do |code|
    num = code.split(".").first
    market = code.end_with?(".SH") ? "SH" : "SZ"
    secid = "#{market}#{num}"
    begin
      url = "/PC_HSF10/NewFinanceAnalysis/ZYZBAjaxNew"
      params = { "type" => "1", "code" => secid }
      resp = nil
      2.times do
        resp = conn.get(url, params)
        break if resp.success?
        sleep 0.4
      end
      if resp&.success?
        data = JSON.parse(resp.body) rescue {}
        roe = nil
        if data["data"] && data["data"].is_a?(Array) && !data["data"].empty?
          latest = data["data"].max_by { |d| d["REPORT_DATE"].to_s }
          roe = latest["ROEJQ"] if latest
        end
        results[code] = roe.to_f if roe && roe.to_f != 0
      end
    rescue StandardError
      # skip individual errors (SSL/timeout/etc)
    end
    sleep 0.15
  end

  results
end

def fetch_roe_hk(codes)
  results = {}
  ut_token = "fa5fd1943c7b386f172d6893dbbd1d0c"
  return results if codes.empty?

  $stderr.puts "[ROE:HK] start fetching #{codes.size} stocks via push2 f167"

  # ===== Method 1: Faraday (fast, shared conn) =====
  conn = Faraday.new(url: "https://push2.eastmoney.com") do |f|
    f.adapter Faraday.default_adapter
    f.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"
    f.ssl[:verify] = false
    f.options[:timeout] = 10
    f.options[:open_timeout] = 6
  end

  codes.each do |code|
    num = code.split(".").first
    secid = "116.#{num}"
    begin
      resp = nil
      2.times do
        resp = conn.get("/api/qt/stock/get", {
          "secid" => secid,
          "fields" => "f167",
          "ut" => ut_token
        })
        break if resp.success?
        sleep 0.4
      end
      if resp&.success?
        data = JSON.parse(resp.body) rescue {}
        dd = data["data"]
        if dd && dd["f167"]
          roe_ttm = dd["f167"].to_f / 100.0
          results[code] = roe_ttm if roe_ttm != 0
        end
      end
    rescue StandardError
      # skip per-stock errors
    end
    sleep 0.08
  end

  # ===== Method 2: shell curl fallback (bypasses Ruby OpenSSL EOF bugs on some macOS/Ruby 3.4) =====
  if results.size < codes.size * 0.5
    $stderr.puts "[ROE:HK] Faraday got #{results.size}/#{codes.size} — trying curl fallback for missing #{codes.size - results.size}..."
    missing = codes.reject { |c| results.key?(c) }
    missing.each do |code|
      num = code.split(".").first
      secid = "116.#{num}"
      out = `curl -sS --max-time 14 --retry 1 \
        -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/129.0 Safari/537.36' \
        -H 'Accept: application/json,text/plain,*/*' \
        --compressed \
        'https://push2.eastmoney.com/api/qt/stock/get?secid=#{secid}&fields=f167&ut=#{ut_token}' 2>/dev/null`
      next unless $?.success? && !out.to_s.strip.empty?
      begin
        dd = JSON.parse(out)["data"]
        if dd && dd["f167"]
          roe_ttm = dd["f167"].to_f / 100.0
          results[code] = roe_ttm if roe_ttm != 0
        end
      rescue StandardError
        # ignore parse errors
      end
      sleep 0.06
    end
  end

  $stderr.puts "[ROE:HK] done: got #{results.size}/#{codes.size}"
  results
end

def fetch_roe_batch(codes)
  a_codes = codes.select { |c| c.end_with?(".SH", ".SZ") }

  a_result = {}
  Thread.report_on_exception = true

  threads = []
  threads << Thread.new do
    Thread.current.name = "roe-a-share"
    begin
      a_result = fetch_roe_a_share(a_codes)
    rescue StandardError => e
      $stderr.puts "[ROE:A] thread FAILED: #{e.class} #{e.message[0..200]}"
      a_result = {}
    end
  end unless a_codes.empty?

  threads.each(&:join)

  $stderr.puts "[ROE:summary] A=#{a_result.size}/#{a_codes.size}  H=SKIPPED total=#{a_result.size}"

  a_result
end

def load_data
  stocks = YAML.load_file(STOCKS_YAML)
  codes = stocks.map { |s| s["code"] }

  puts "🌐 正在拉取实时价格 (#{codes.size} 只)..."
  prices = fetch_realtime_prices(codes)
  puts "✅ 获取 #{prices.size} 只实时价格"
  if prices.size < codes.size
    miss = codes.size - prices.size
    puts "⚠️  缺失 #{miss} 只价格"
  end

  puts "📊 正在拉取 ROE 数据 (仅 A 股)..."
  roes = fetch_roe_batch(codes)
  total_a = codes.count { |c| c.end_with?(".SH", ".SZ") }
  a_n  = roes.count { |c, _| c.end_with?(".SH", ".SZ") }
  puts "✅ 获取 #{roes.size} 只 ROE (A股 #{a_n}/#{total_a}, 港股已跳过)"

  stocks.each do |s|
    code = s["code"]
    if prices[code] && prices[code]["current_price"] > 0
      s["current_price"] = prices[code]["current_price"]
      s["price_date"] = "#{prices[code]["date"]} #{prices[code]["time"]}"
    else
      s["current_price"] = nil
      s["price_date"] = nil
    end
    s["roe"] = roes[code] if roes[code]
  end

  stocks
end

def process(stocks)
  stocks.each do |s|
    cur = s["current_price"]
    buy = s["buy_price"]
    s["need_drop_pct"] = if cur && cur > 0 && buy > 0
                           (cur - buy) / cur * 100.0
                         else
                           Float::INFINITY
                         end
  end

  stocks.sort_by! { |s| s["need_drop_pct"] }
end

CORE_CATEGORY_PREFIXES = [
  "银行", "电力/", "公用事业/", "交运/", "金融/保险", "通信/运营商",
  "能源/油气开采", "周期/煤炭", "基建/公用"
].freeze

def satellite_category?(category)
  CORE_CATEGORY_PREFIXES.none? { |p| category.start_with?(p) }
end

def calc_stats(stocks)
  priced = stocks.select { |s| s["current_price"] }
  below = priced.count { |s| s["current_price"] < s["buy_price"] }
  near = priced.count { |s| s["need_drop_pct"] >= 0 && s["need_drop_pct"] < 5 }
  mid = priced.count { |s| s["need_drop_pct"] >= 5 && s["need_drop_pct"] < 10 }
  far = priced.count { |s| s["need_drop_pct"] >= 10 && !s["need_drop_pct"].infinite? }
  roes = stocks.map { |s| s["roe"] }.compact
  drops = priced.map { |s| s["need_drop_pct"] }

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
stocks.each { |s| s["satellite"] = satellite_category?(s["category"]) }
stats = calc_stats(stocks)
categories = stocks.map { |s| s["category"] }.uniq.sort
generated_at = Time.now.getlocal("+08:00").strftime("%Y-%m-%d %H:%M:%S (UTC+8)")

template = Erubi::Engine.new(TEMPLATE_ERB, escape: true)
html = eval(template.src)
File.write(INDEX_HTML, html)
puts "页面已生成: #{INDEX_HTML}"
puts "统计: 跌破#{stats[:below_count]}只 | 平均需跌#{stats[:avg_drop]}% | 平均ROE#{stats[:avg_roe]}%"
