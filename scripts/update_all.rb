#!/usr/bin/env ruby
require "fileutils"

ROOT = File.expand_path("..", __dir__)

puts "=== Step 1/2: 拉取最新价格和ROE ==="
system("ruby", File.join(ROOT, "scripts/fetch_prices.rb")) || abort("拉取价格失败")

puts
puts "=== Step 2/2: 生成最新HTML页面 ==="
system("ruby", File.join(ROOT, "scripts/generate_page.rb")) || abort("生成页面失败")

puts
puts "✅ 全部完成！打开 public/index.html 查看结果"
