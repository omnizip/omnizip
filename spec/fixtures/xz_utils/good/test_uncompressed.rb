#!/usr/bin/env ruby
require_relative "lib/omnizip"

# Test uncompressed chunk handling
# good-1-empty-bcj-lzma2.xz contains an uncompressed chunk followed by LZMA2 chunks

data = File.binread("./good-1-empty-bcj-lzma2.xz")

begin
  reader = Omnizip::Formats::Xz::Reader.new(StringIO.new(data))
  result = reader.read
  puts "Success! Output size: #{result.bytesize} bytes"
  puts "First 50 bytes: #{result[0, 50].inspect}"
rescue StandardError => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(10)
end
