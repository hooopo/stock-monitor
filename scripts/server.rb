#!/usr/bin/env ruby
# frozen_string_literal: true
# Simple WEBrick HTTP server that:
#   a) serves static files from /public under /
#   b) proxies /api/sina?list=<codes> to https://hq.sinajs.cn/list=<codes>
#      with Referer and UA set (to avoid Sina 403 Forbidden without Referer)
#      and transcodes Sina GBK body to UTF-8.
#   c) mirrors the Cloudflare Worker contract at GET /cfw/?list=<sh,sz,r_hk>
#      returning application/json { shNNNNNN: price, sz..., r_hk... } with
#      Access-Control-Allow-Origin:*.  This makes `PORT=... ruby scripts/server.rb`
#      a 100% local substitute for the Cloudflare Worker, so you can set
#      STOCK_PROXY_BASE = "http://127.0.0.1:8765/cfw" (or /cfw proxy mount)
#      in-browser and test the exact proxy code path without deploying.
require "webrick"
require "net/http"
require "uri"
require "json"

ROOT_DIR = File.expand_path("..", __dir__)
PUBLIC_DIR = File.join(ROOT_DIR, "public")
SINA_HOST = "hq.sinajs.cn"
QQ_HOST = "qt.gtimg.cn"
SINA_REF = "https://finance.sina.com.cn/"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
     "(KHTML, like Gecko) Chrome/129.0 Safari/537.36"

def sina_proxy(list_param, res)
  return res.status = 400 unless list_param && !list_param.empty?

  uri = URI("https://#{SINA_HOST}/list=#{list_param}")
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 8
  http.read_timeout = 10
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = UA
  req["Referer"] = SINA_REF
  req["Accept-Language"] = "zh-CN,zh;q=0.9"
  resp = http.request(req)
  body = resp.body || ""
  begin
    body.force_encoding("GBK")
    body = body.encode("UTF-8", invalid: :replace, undef: :replace)
  rescue StandardError
    # leave as-is
  end
  res.status = resp.is_a?(Net::HTTPSuccess) ? 200 : 502
  res["Content-Type"] = "application/javascript; charset=utf-8"
  res["Cache-Control"] = "no-store"
  res.body = body
end

port = (ENV["PORT"] || 8765).to_i
host = ENV["HOST"] || "127.0.0.1"

server = WEBrick::HTTPServer.new(
  Port: port,
  BindAddress: host,
  AccessLog: [],
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::WARN)
)

server.mount_proc "/api/sina" do |req, res|
  list = req.query["list"]
  sina_proxy(list, res)
end

def gbk_to_utf8(bytes)
  s = String.new("")
  begin
    s = (bytes || "").dup.force_encoding("GBK").encode("UTF-8", invalid: :replace, undef: :replace)
  rescue StandardError
    s = (bytes || "").dup.force_encoding("UTF-8") rescue (bytes || "")
  end
  s
end

def normalize_qq_codes(raw)
  return [] unless raw && !raw.empty?
  raw.to_s.split(",").map(&:strip).map(&:downcase).select do |t|
    next false if t.empty?
    t = "r_#{t}" if t.match?(/^hk\d{5}$/)
    t.match?(/^(sh\d{6}|sz\d{6}|r_hk\d{5})$/)
  end.uniq
end

def fetch_qq_batch(codes)
  out = {}
  return out if codes.empty?
  uri = URI("https://#{QQ_HOST}/q=#{URI.encode_www_form_component(codes.join(','))}")
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 8
  http.read_timeout = 12
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = UA
  req["Accept"] = "*/*"
  resp = http.request(req)
  return out unless resp.is_a?(Net::HTTPSuccess)
  text = gbk_to_utf8(resp.body || "")
  text.split(/\n|;/).map(&:strip).reject(&:empty?).each do |line|
    m = /v_(r_hk\d+|[sh]z\d+)="([^"]*)"/.match(line)
    next unless m
    key = m[1]
    fields = m[2].split("~")
    p = Float(fields[3] || "0", exception: false) || 0
    out[key] = p if p > 0
  end
  out
end

def sina_key_to_qq(sina_key)
  # sina key: hq_str_hk00700 / hq_str_sh600036
  inner = sina_key.to_s.sub(/^hq_str_/, "")
  return "r_#{inner}" if inner.match?(/^hk\d{5}$/)
  inner
end

def fetch_sina_batch_for_qqkeys(qq_keys)
  out = {}
  return out if qq_keys.empty?
  # sina upstream keys: shNNNNNN / szNNNNNN / hkNNNNN (no r_)
  sina_keys = qq_keys.map do |q|
    next q[2..] if q.start_with?("r_") # r_hkNNNNN -> hkNNNNN
    q
  end
  uri = URI("https://#{SINA_HOST}/list=#{sina_keys.join(',')}")
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 8
  http.read_timeout = 12
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = UA
  req["Referer"] = SINA_REF
  req["Accept"] = "*/*"
  resp = http.request(req)
  return out unless resp.is_a?(Net::HTTPSuccess)
  text = gbk_to_utf8(resp.body || "")
  text.split(/\n|;/).map(&:strip).reject(&:empty?).each do |line|
    m = /(hq_str_[a-z_]+\d+)="([^"]*)"/.match(line)
    next unless m
    qq = sina_key_to_qq(m[1])
    next unless qq_keys.include?(qq)
    fields = m[2].split(",")
    p = if qq.start_with?("r_hk")
          Float(fields[6] || fields[2] || "0", exception: false) || 0
        else
          Float(fields[3] || "0", exception: false) || 0
        end
    out[qq] = p if p > 0
  end
  out
end

MAX_CFW_BATCH = 80

def cfw_proxy(raw_list, res)
  codes = normalize_qq_codes(raw_list)
  status = 200
  payload = if codes.empty?
              status = 400
              { error: "empty or invalid ?list= (expected sh/sz/r_hk codes)",
                example: "/cfw/?list=sh600036,sz000001,r_hk00700" }
            else
              result = {}
              (0...codes.size).step(MAX_CFW_BATCH) do |i|
                batch = codes[i, MAX_CFW_BATCH]
                qq = fetch_qq_batch(batch) rescue {}
                result.merge!(qq)
                missing = batch - qq.keys
                next if missing.empty?
                begin
                  sina = fetch_sina_batch_for_qqkeys(missing)
                  result.merge!(sina)
                rescue StandardError
                  # ignore
                end
              end
              result
            end
  res.status = status
  res["Content-Type"] = "application/json; charset=utf-8"
  res["Access-Control-Allow-Origin"] = "*"
  res["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  res["Access-Control-Allow-Headers"] = "*"
  res["Cache-Control"] = "no-store"
  res.body = JSON.generate(payload)
end

# OPTIONS preflight helper — apply to /cfw and /api/sina
def apply_cors(res)
  res["Access-Control-Allow-Origin"] = "*"
  res["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  res["Access-Control-Allow-Headers"] = "*"
  res["Access-Control-Max-Age"] = "86400"
end

server.mount_proc "/cfw" do |req, res|
  if req.request_method == "OPTIONS"
    res.status = 204
    apply_cors(res)
    next
  end
  if req.request_method != "GET"
    res.status = 405
    apply_cors(res)
    res["Content-Type"] = "application/json"
    res.body = JSON.generate(error: "method not allowed")
    next
  end
  cfw_proxy(req.query["list"], res)
end
# also mount / — proxy contract expects /?list=...
server.mount_proc "/cfw/" do |req, res|
  if req.request_method == "OPTIONS"
    res.status = 204
    apply_cors(res)
    next
  end
  next unless req.request_method == "GET"
  cfw_proxy(req.query["list"], res)
end

server.mount "/", WEBrick::HTTPServlet::FileHandler, PUBLIC_DIR

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

$stdout.sync = true
puts "stock-buy server listening on http://#{host}:#{port}/  (serving #{PUBLIC_DIR})"
puts "  /api/sina?list=sh600036,sz000001,hk00700        proxy -> hq.sinajs.cn with Referer"
puts "  /cfw?list=sh600036,sz000001,r_hk00700         Cloudflare Worker-compatible proxy -> JSON (A+H)"
puts "  usage: set STOCK_PROXY_BASE=\"http://#{host}:#{port}/cfw\" in browser console to simulate CF Worker"
server.start
