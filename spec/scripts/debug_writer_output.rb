#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../../lib/omnizip/formats/seven_zip/writer"
require_relative "../../lib/omnizip/formats/seven_zip/reader"
require_relative "../../lib/omnizip/formats/seven_zip/constants"
require "tempfile"

include Omnizip::Formats::SevenZip::Constants

# Create a test archive
test_file = Tempfile.new(["test", ".txt"])
test_file.write("Hello, World!")
test_file.close

output = Tempfile.new(["test", ".7z"])
output.close

puts "Creating archive..."
writer = Omnizip::Formats::SevenZip::Writer.new(output.path)
writer.add_file(test_file.path, "test.txt")
writer.write

puts "\nAnalyzing archive structure:"
File.open(output.path, "rb") do |io|
  # Read signature
  sig = io.read(6)
  puts "Signature: #{sig.bytes.map { |b| format('0x%02X', b) }.join(' ')}"

  # Read version
  version = io.read(2)
  puts "Version: #{version.bytes.map { |b| format('0x%02X', b) }.join(' ')}"

  # Read start header CRC
  crc = io.read(4).unpack1("V")
  puts "Start Header CRC: 0x#{format('%08X', crc)}"

  # Read next header offset
  offset = io.read(8).unpack1("Q<")
  puts "Next Header Offset: #{offset}"

  # Read next header size
  size = io.read(8).unpack1("Q<")
  puts "Next Header Size: #{size}"

  # Read next header CRC
  next_crc = io.read(4).unpack1("V")
  puts "Next Header CRC: 0x#{format('%08X', next_crc)}"

  # Jump to next header
  io.seek(32 + offset)
  puts "\nNext header position: #{io.pos}"

  # Read first 20 bytes of next header
  next_header_bytes = io.read([size, 20].min)
  puts "First bytes of next header:"
  next_header_bytes.bytes.each_with_index do |byte, i|
    prop_name = case byte
                when PropertyId::K_END then "K_END"
                when PropertyId::HEADER then "HEADER"
                when PropertyId::ENCODED_HEADER then "ENCODED_HEADER"
                when PropertyId::MAIN_STREAMS_INFO then "MAIN_STREAMS_INFO"
                when PropertyId::FILES_INFO then "FILES_INFO"
                when PropertyId::PACK_INFO then "PACK_INFO"
                when PropertyId::UNPACK_INFO then "UNPACK_INFO"
                end

    if prop_name
      puts "  [#{i}] 0x#{format('%02X', byte)} (#{byte}) - #{prop_name}"
    else
      puts "  [#{i}] 0x#{format('%02X', byte)} (#{byte})"
    end
  end
end

puts "\nAttempting to read archive..."
begin
  reader = Omnizip::Formats::SevenZip::Reader.new(output.path)
  reader.open
  puts "SUCCESS: Archive can be read!"
  reader.entries.each do |entry|
    puts "  Entry: #{entry.name}"
  end
  reader.close
rescue StandardError => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Cleanup
test_file.unlink
File.unlink(output.path)
