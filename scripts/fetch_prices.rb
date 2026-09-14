#!/usr/bin/env ruby
require "yaml"
require "json"
require "faraday"

STOCKS_YAML = File.expand_path("../data/stocks.yml", __dir__)
PRICES_JSON = File.expand_path("../data/prices.json", __dir__)

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

      price = fields[3].to_f
      name = fields[0]
      results[orig_code] = {
        "name" => name,
        "current_price" => price,
        "open" => fields[1].to_f,
        "prev_close" => fields[2].to_f,
        "high" => fields[4].to_f,
        "low" => fields[5].to_f,
        "volume" => fields[8].to_i,
        "amount" => fields[9].to_f,
        "date" => fields[30],
        "time" => fields[31]
      }
    end
    sleep 0.5
  end

  results
end

def fetch_roe_batch(codes)
  results = {}
  conn = Faraday.new(url: "https://emweb.securities.eastmoney.com") do |f|
    f.adapter Faraday.default_adapter
  end

  codes.each do |code|
    num = code.split(".").first
    market = code.end_with?(".SH") ? "SH" : "SZ"
    secid = "#{market}#{num}"
    begin
      url = "/PC_HSF10/NewFinanceAnalysis/ZYZBAjaxNew"
      params = {
        "type" => "0",
        "code" => secid
      }
      resp = conn.get(url, params)
      if resp.success?
        data = JSON.parse(resp.body) rescue {}
        roe = nil
        if data["data"] && data["data"].is_a?(Array) && !data["data"].empty?
          latest = data["data"].max_by { |d| d["REPORT_DATE"].to_s }
          roe = latest["ROEJQ"] if latest
        end
        results[code] = roe.to_f if roe && roe.to_f != 0
      end
    rescue => e
      # skip individual errors
    end
    sleep 0.15
  end

  results
end

stocks = YAML.load_file(STOCKS_YAML)
codes = stocks.map { |s| s["code"] }

puts "正在拉取实时价格 (#{codes.size} 只股票)..."
prices = fetch_realtime_prices(codes)
puts "成功获取 #{prices.size} 只股票的实时价格"

puts "正在拉取 ROE 数据..."
roes = fetch_roe_batch(codes)
puts "成功获取 #{roes.size} 只股票的 ROE"

stocks.each do |s|
  code = s["code"]
  if prices[code]
    s["current_price"] = prices[code]["current_price"]
    s["price_date"] = "#{prices[code]["date"]} #{prices[code]["time"]}"
  else
    s["current_price"] ||= s["reference_price"]
    s["price_date"] ||= "参考价"
  end
  s["roe"] = roes[code] if roes[code]
end

File.write(PRICES_JSON, JSON.pretty_generate(stocks))
puts "数据已保存到 #{PRICES_JSON}"
