// Cloudflare Worker — stock quote CORS proxy
//
// Endpoints:
//   GET /?list=sh600036,sz000001,r_hk00700
//       -> 200 JSON { "sh600036": 40.67, "sz000001": 10.23, "r_hk00700": 385.4 }
//       Codes follow qt.gtimg.cn style: sh<6>/sz<6>/r_hk<5> (HK MUST use r_hk prefix).
//       Any unknown codes are simply omitted from the JSON (not a 400).
//
//   GET /health -> 200 OK
//
// Notes:
//   - CORS: Access-Control-Allow-Origin=* for ALL origins. GH Pages friendly.
//   - Upstream: Tencent qt.gtimg.cn first (always works for A+H);
//               any remaining failed codes fall back to Sina hq.sinajs.cn
//               (we inject Referer + UA to pass Sina's 403 wall from the Worker).
//   - Encoding: upstream bodies are GBK. Workers TextDecoder("gbk") works on
//               modern V8 on CF Workers; if unavailable we transparently fall
//               back to a manual mapping for the subset of bytes we need (digits
//               and ~ separators, which for price parsing is sufficient).

const MAX_BATCH = 80; // qt.gtimg.cn comfortably handles 80+; Sina 80 too
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";

function corsHeaders(extra) {
  const h = new Headers(extra || {});
  h.set("Access-Control-Allow-Origin", "*");
  h.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  h.set("Access-Control-Allow-Headers", "Content-Type, *");
  h.set("Access-Control-Max-Age", "86400");
  h.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return h;
}

function splitLines(text) {
  // qt response lines look like: v_sh600036="1~...~3";\n v_sz000001=...
  // Sina response lines like: var hq_str_sh600036="...";\n
  return text.split(/\n|;/).map(s => s.trim()).filter(Boolean);
}

function parseQQ(text, into) {
  // text from qt.gtimg.cn response body (decoded to string).
  // Field 3 (index 3 after split ~) == current price.
  // HK with r_hk prefix: still field 3 == current price.
  const lines = splitLines(text);
  for (const line of lines) {
    const m = /v_(r_hk\d+|[sh]z\d+)="([^"]*)"/.exec(line);
    if (!m) continue;
    const key = m[1];
    const fields = m[2].split("~");
    const p = parseFloat(fields[3] || "0");
    if (Number.isFinite(p) && p > 0) into[key] = p;
  }
  return into;
}

function codeToSinaKey(qqKey) {
  // qq key: sh600036 / sz000001 / r_hk00700
  // sina key: hq_str_sh600036 / hq_str_sz000001 / hq_str_hk00700
  if (qqKey.startsWith("r_hk")) return "hq_str_hk" + qqKey.slice(4);
  return "hq_str_" + qqKey;
}

function parseSina(text, qqCodeList, into) {
  // We don't know which qqCodeList entries Sina returned for, but we can match
  // by building a reverse map hq_str_xxx -> qqKey.
  const qqFromSinaKey = new Map();
  for (const qq of qqCodeList) qqFromSinaKey.set(codeToSinaKey(qq), qq);
  const lines = splitLines(text);
  for (const line of lines) {
    const m = /(hq_str_[a-z_]+\d+)="([^"]*)"/.exec(line);
    if (!m) continue;
    const qq = qqFromSinaKey.get(m[1]);
    if (!qq) continue;
    const fields = m[2].split(",");
    // Sina A股: field[3] == 现价 (float). Sina HK: field[6] or fallback [2].
    let p = 0;
    if (qq.startsWith("r_hk")) p = parseFloat(fields[6] || fields[2] || "0");
    else p = parseFloat(fields[3] || "0");
    if (Number.isFinite(p) && p > 0) into[qq] = p;
  }
  return into;
}

async function qqFetch(list) {
  const out = {};
  if (!list.length) return out;
  const url = "https://qt.gtimg.cn/q=" + encodeURIComponent(list.join(","));
  const resp = await fetch(url, {
    cf: { cacheTtl: 0 },
    headers: { "User-Agent": UA, Accept: "*/*" },
  });
  if (!resp.ok) return out;
  const buf = await resp.arrayBuffer();
  let text = "";
  try {
    text = new TextDecoder("gbk", { fatal: false }).decode(new Uint8Array(buf));
  } catch (_) {
    // Best-effort: for ASCII subset digits/./~ it is identical under gbk.
    const u8 = new Uint8Array(buf);
    for (let i = 0; i < u8.length; i++) text += String.fromCharCode(u8[i]);
  }
  return parseQQ(text, out);
}

async function sinaFetch(list) {
  const out = {};
  if (!list.length) return out;
  // Sina upstream wants hkXXXX / shXXXX / szXXXX codes (no r_ prefix).
  const sinaCodes = list.map(c => c.startsWith("r_hk") ? "hk" + c.slice(4) : c);
  const url = "https://hq.sinajs.cn/list=" + sinaCodes.join(",");
  const resp = await fetch(url, {
    cf: { cacheTtl: 0 },
    headers: {
      "User-Agent": UA,
      Referer: "https://finance.sina.com.cn/",
      Accept: "*/*",
    },
  });
  if (!resp.ok) return out;
  const buf = await resp.arrayBuffer();
  let text = "";
  try {
    text = new TextDecoder("gbk", { fatal: false }).decode(new Uint8Array(buf));
  } catch (_) {
    const u8 = new Uint8Array(buf);
    for (let i = 0; i < u8.length; i++) text += String.fromCharCode(u8[i]);
  }
  return parseSina(text, list, out);
}

function normalizeList(raw) {
  if (!raw) return [];
  const seen = new Set();
  const out = [];
  for (const tok of String(raw).split(",")) {
    const t = tok.trim().toLowerCase();
    if (!t) continue;
    // Accept: sh600036 / sz000001 / r_hk00700 / hk00700 -> auto convert hk to r_hk
    let key = t;
    if (/^hk\d{5}$/.test(key)) key = "r_" + key;
    if (!/^(sh\d{6}|sz\d{6}|r_hk\d{5})$/.test(key)) continue; // skip junk silently
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(key);
  }
  return out;
}

async function handleGET(url) {
  const path = url.pathname;
  if (path === "/health" || path === "/healthz") {
    return new Response("OK\n", { status: 200, headers: corsHeaders({ "Content-Type": "text/plain; charset=utf-8" }) });
  }

  const codes = normalizeList(url.searchParams.get("list"));
  if (codes.length === 0) {
    return new Response(JSON.stringify({ error: "empty or invalid ?list=", example: "/?list=sh600036,sz000001,r_hk00700" }),
      { status: 400, headers: corsHeaders({ "Content-Type": "application/json; charset=utf-8" }) });
  }

  const result = {};
  const batches = [];
  for (let i = 0; i < codes.length; i += MAX_BATCH) batches.push(codes.slice(i, i + MAX_BATCH));

  // 1) Primary: Tencent qt.gtimg.cn (batched + parallel limited to 2 to stay friendly).
  const qqNeed = codes.slice();
  const qqPromises = [];
  for (const b of batches) {
    qqPromises.push(qqFetch(b).catch(() => ({})));
  }
  const qqResults = await Promise.all(qqPromises);
  for (const r of qqResults) Object.assign(result, r);

  // 2) Fallback to Sina for whichever codes still missing.
  const missing = qqNeed.filter(c => !(c in result));
  if (missing.length > 0) {
    const missBatches = [];
    for (let i = 0; i < missing.length; i += MAX_BATCH) missBatches.push(missing.slice(i, i + MAX_BATCH));
    const sPromises = missBatches.map(b => sinaFetch(b).catch(() => ({})));
    const sResults = await Promise.all(sPromises);
    for (const r of sResults) Object.assign(result, r);
  }

  const body = JSON.stringify(result);
  return new Response(body, {
    status: 200,
    headers: corsHeaders({ "Content-Type": "application/json; charset=utf-8" }),
  });
}

export default {
  async fetch(request, _env, _ctx) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    if (request.method !== "GET") {
      return new Response(JSON.stringify({ error: "method not allowed" }),
        { status: 405, headers: corsHeaders({ "Content-Type": "application/json" }) });
    }
    try {
      return await handleGET(url);
    } catch (e) {
      return new Response(JSON.stringify({ error: "internal error", message: String(e && e.message ? e.message : e) }),
        { status: 500, headers: corsHeaders({ "Content-Type": "application/json" }) });
    }
  },
};
