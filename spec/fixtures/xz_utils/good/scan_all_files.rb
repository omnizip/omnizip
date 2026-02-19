#!/usr/bin/env ruby

files = [
  "good-1-lzma2-1.xz",
  "good-1-lzma2-2.xz",
  "good-1-lzma2-3.xz",
]

files.each do |filename|
  puts "\n=== #{filename} ==="
  data = File.binread(filename)
  bytes = data.bytes

  # Just scan for LZMA2 control bytes
  pos = 24 # LZMA2 data starts at byte 24
  chunk_num = 0
  while pos < 400 && chunk_num < 5
    control = bytes[pos]

    if control == 0
      puts "Chunk #{chunk_num}: control=0x00 (end marker)"
      break
    elsif control.nobits?(0x80) && control != 0
      # Uncompressed chunk
      puts "Chunk #{chunk_num}: control=0x#{control.to_s(16).upcase} (uncompressed)"
      pos += 1
      uncompressed_size = (control & 0x1F) << 16
      uncompressed_size |= bytes[pos] << 8
      pos += 1
      uncompressed_size |= bytes[pos]
      pos += 1
      pos += uncompressed_size
    elsif control.anybits?(0x80)
      # LZMA chunk
      dict_reset = control.anybits?(0x40)
      has_props = control.anybits?(0x20)

      uncompressed_high = control & 0x1F
      uncompressed_low = (bytes[pos + 1] << 8) | bytes[pos + 2]
      uncompressed_size = (uncompressed_high << 16) + uncompressed_low + 1

      compressed_size = ((bytes[pos + 3] << 8) | bytes[pos + 4]) + 1

      type = if dict_reset && has_props
               "dict reset + state reset + props"
             elsif has_props
               "state reset + props"
             else
               "compressed chunk"
             end

      puts "Chunk #{chunk_num}: control=0x#{control.to_s(16).upcase} (#{type})"
      puts "  Uncompressed: #{uncompressed_size} bytes, Compressed: #{compressed_size} bytes"

      # Calculate next chunk position
      next_pos = pos + 5 # control + sizes
      if dict_reset || has_props
        props = bytes[pos + 5]
        puts "  Properties: 0x#{props.to_s(16).upcase}"
        next_pos += 1
      end
      next_pos += compressed_size
      pos = next_pos
    end

    chunk_num += 1
  end
end
