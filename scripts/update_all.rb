#!/usr/bin/env ruby
require "fileutils"

ROOT = File.expand_path("..", __dir__)

puts "=== 生成最新页面 (实时抓取价格+ROE) ==="
system("ruby", File.join(ROOT, "scripts/generate_page.rb")) || abort("生成页面失败")

puts
puts "✅ 全部完成！打开 public/index.html 查看结果"
