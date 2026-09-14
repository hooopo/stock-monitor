#!/usr/bin/env ruby
require "csv"
require "yaml"

CSV_PATH = File.expand_path("../stock_csv.csv", __dir__)
YAML_PATH = File.expand_path("../data/stocks.yml", __dir__)

stocks = []
CSV.foreach(CSV_PATH, headers: true, encoding: "UTF-8") do |row|
  stocks << {
    "name" => row["股票"].to_s.strip,
    "code" => row["证券代码"].to_s.strip,
    "category" => row["分类"].to_s.strip,
    "reference_price" => row["现价_参考"].to_s.gsub(",", "").to_f,
    "buy_price" => row["首仓价"].to_s.gsub(",", "").to_f
  }
end

File.write(YAML_PATH, YAML.dump(stocks))
puts "已转换 #{stocks.size} 条记录到 #{YAML_PATH}"
