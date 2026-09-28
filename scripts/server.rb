#!/usr/bin/env ruby
# frozen_string_literal: true
# Simple WEBrick HTTP server that:
#   a) serves static files from /public under /
#   b) proxies /api/sina?list=<codes> to https://hq.sinajs.cn/list=<codes>
#      with Referer and UA set (to avoid Sina 403 Forbidden without Referer)
#      and transcodes Sina GBK body to UTF-8.
require "webrick"
require "net/http"
require "uri"

ROOT_DIR = File.expand_path("..", __dir__)
PUBLIC_DIR = File.join(ROOT_DIR, "public")
SINA_HOST = "hq.sinajs.cn"
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

server.mount "/", WEBrick::HTTPServlet::FileHandler, PUBLIC_DIR

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

$stdout.sync = true
puts "stock-buy server listening on http://#{host}:#{port}/  (serving #{PUBLIC_DIR})"
puts "  /api/sina?list=sh600036,sz000001,hk00700 proxy -> hq.sinajs.cn with Referer"
server.start
