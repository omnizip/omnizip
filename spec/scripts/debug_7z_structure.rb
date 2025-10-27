#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../../lib/omnizip/formats/seven_zip/header"
require_relative "../../lib/omnizip/formats/seven_zip/parser"
require_relative "../../lib/omnizip/formats/seven_zip/constants"

include Omnizip::Formats::SevenZip::Constants

def show_property(id)
  case id
  when PropertyId::K_END then "END(0x00)"
  when PropertyId::HEADER then "HEADER(0x01)"
  when PropertyId::MAIN_STREAMS_INFO then "MAIN_STREAMS_INFO(0x04)"
  when PropertyId::FILES_INFO then "FILES_INFO(0x05)"
  when PropertyId::PACK_INFO then "PACK_INFO(0x06)"
  when PropertyId::UNPACK_INFO then "UNPACK_INFO(0x07)"
  when PropertyId::SUBSTREAMS_INFO then "SUBSTREAMS_INFO(0x08)"
  when PropertyId::SIZE then "SIZE(0x09)"
  when PropertyId::CRC then "CRC(0x0A)"
  when PropertyId::FOLDER then "FOLDER(0x0B)"
  when PropertyId::CODERS_UNPACK_SIZE then "CODERS_UNPACK_SIZE(0x0C)"
  when PropertyId::NAME then "NAME(0x11)"
  else "UNKNOWN(0x#{id.to_s(16)})"
  end
end

file_path = ARGV[0] || "spec/fixtures/seven_zip/simple_lzma.7z"

File.open(file_path, "rb") do |io|
  header = Omnizip::Formats::SevenZip::Header.read(io)
  puts "Header parsed successfully"
  puts "Next header offset: #{header.next_header_offset}"
  puts "Next header size: #{header.next_header_size}"

  # Read next header
  io.seek(header.start_pos_after_header + header.next_header_offset)
  next_header_data = io.read(header.next_header_size)

  parser = Omnizip::Formats::SevenZip::Parser.new(next_header_data)

  puts "\nParsing structure:"
  depth = 0
  until parser.eof?
    b = parser.peek_byte
    puts ("  " * depth) + "Position #{parser.position}: #{show_property(b)}"

    parser.read_byte
    case b
    when PropertyId::HEADER, PropertyId::MAIN_STREAMS_INFO,
             PropertyId::PACK_INFO, PropertyId::UNPACK_INFO,
             PropertyId::SUBSTREAMS_INFO, PropertyId::FILES_INFO
      depth += 1
    when PropertyId::K_END
      depth -= 1
    when PropertyId::FOLDER
      num_folders = parser.read_number
      puts ("  " * depth) + "  Number of folders: #{num_folders}"
      depth += 1
    else
      break if parser.eof?
    end

    break if depth < 0
  end
end
