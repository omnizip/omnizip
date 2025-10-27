# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe "Delta Filter Integration" do
  let(:lzma) { Omnizip::Algorithms::LZMA.new }
  let(:lzma2) { Omnizip::Algorithms::LZMA2.new }

  describe "with LZMA compression" do
    it "improves compression of audio-like data" do
      # Generate audio-like data (gradual changes)
      audio_data = (0..1023).map { |i| (i % 256) }.pack("C*")

      # Compress without filter
      plain_out = StringIO.new
      lzma.compress(StringIO.new(audio_data), plain_out)
      plain_compressed = plain_out.string

      # Compress with Delta filter
      delta = Omnizip::Filters::Delta.new(1)
      filtered_data = delta.encode(audio_data)
      filtered_out = StringIO.new
      lzma.compress(StringIO.new(filtered_data), filtered_out)
      filtered_compressed = filtered_out.string

      # Delta should improve compression
      expect(filtered_compressed.bytesize).to be < plain_compressed.bytesize

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(filtered_compressed), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(audio_data)
    end

    it "improves compression of RGB image-like data" do
      # Generate RGB image-like data (repeating pixels)
      rgb_data = ([128, 130, 132] * 400).pack("C*")

      # Compress without filter
      plain_out = StringIO.new
      lzma.compress(StringIO.new(rgb_data), plain_out)
      plain_compressed = plain_out.string

      # Compress with Delta filter (distance=3 for RGB)
      delta = Omnizip::Filters::Delta.new(3)
      filtered_data = delta.encode(rgb_data)
      filtered_out = StringIO.new
      lzma.compress(StringIO.new(filtered_data), filtered_out)
      filtered_compressed = filtered_out.string

      # Delta should significantly improve compression
      expect(filtered_compressed.bytesize).to be < plain_compressed.bytesize

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(filtered_compressed), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(rgb_data)
    end

    it "handles database-like data with 32-bit integers" do
      # Generate sequential 32-bit integers
      db_data = (1000..1255).map { |i| i }.pack("V*")

      # Compress with Delta filter (distance=4 for 32-bit)
      delta = Omnizip::Filters::Delta.new(4)
      filtered_data = delta.encode(db_data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered_data), compressed_out)

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(db_data)
    end
  end

  describe "with LZMA2 compression" do
    it "works correctly with chunked compression" do
      # Large audio-like data to trigger multiple chunks
      data = (0..4095).map { |i| (i % 256) }.pack("C*")

      delta = Omnizip::Filters::Delta.new(1)
      filtered_data = delta.encode(data)
      compressed_out = StringIO.new
      lzma2.compress(StringIO.new(filtered_data), compressed_out)

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma2.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(data)
    end
  end

  describe "with FilterPipeline" do
    it "can be used in a filter pipeline" do
      data = (0..511).map { |i| (i % 256) }.pack("C*")

      pipeline = Omnizip::FilterPipeline.new
      delta = Omnizip::Filters::Delta.new(1)
      pipeline.add_filter(delta)

      # Encode through pipeline
      encoded = pipeline.encode(data)
      expect(encoded).not_to eq(data)

      # Decode through pipeline
      decoded = pipeline.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "does not conflict with BCJ filter" do
      # Create some binary data that could be executable-like
      data = ([0xE8, 0x00, 0x00, 0x00, 0x00] * 100).pack("C*")

      # Create pipeline with both filters
      pipeline = Omnizip::FilterPipeline.new
      pipeline.add_filter(Omnizip::Filters::Delta.new(1))
      pipeline.add_filter(Omnizip::Filters::BcjX86.new)

      # Encode and decode
      encoded = pipeline.encode(data)
      decoded = pipeline.decode(encoded)

      # Should round-trip correctly
      expect(decoded).to eq(data)
    end
  end

  describe "compression ratio improvements" do
    it "shows significant improvement for repeating patterns" do
      # Highly compressible pattern after delta
      pattern = [100, 101, 102, 103] * 250
      data = pattern.pack("C*")

      # Without Delta
      plain_out = StringIO.new
      lzma.compress(StringIO.new(data), plain_out)
      plain_size = plain_out.string.bytesize

      # With Delta (distance=1)
      delta = Omnizip::Filters::Delta.new(1)
      filtered = delta.encode(data)
      delta_out = StringIO.new
      lzma.compress(StringIO.new(filtered), delta_out)
      delta_size = delta_out.string.bytesize

      # Should see improvement (at least 10% better)
      improvement_ratio = (plain_size - delta_size).to_f / plain_size
      expect(improvement_ratio).to be > 0.1
    end

    it "may not help with random data" do
      # Random data should not compress better with Delta
      data = Array.new(1000) { rand(256) }.pack("C*")

      plain_out = StringIO.new
      lzma.compress(StringIO.new(data), plain_out)
      plain_out.string.bytesize

      delta = Omnizip::Filters::Delta.new(1)
      filtered = delta.encode(data)
      delta_out = StringIO.new
      lzma.compress(StringIO.new(filtered), delta_out)

      # Delta might not help with truly random data
      # Just verify round-trip works
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(delta_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(data)
    end
  end

  describe "practical multimedia scenarios" do
    it "handles WAV-like mono audio data" do
      # Simulate 16-bit mono audio samples (little-endian)
      samples = (0..511).map { |i| (32_768 + (i * 10)) % 65_536 }
      wav_data = samples.pack("v*")

      # Use distance=2 for 16-bit stereo channels
      delta = Omnizip::Filters::Delta.new(2)
      filtered = delta.encode(wav_data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(wav_data)
      expect(restored.unpack("v*")).to eq(samples)
    end

    it "handles BMP-like 24-bit RGB image data" do
      # Simulate RGB pixels with gradual color changes
      pixels = (0..299).map do |i|
        r = (100 + (i / 10)) % 256
        g = (150 + (i / 10)) % 256
        b = (200 + (i / 10)) % 256
        [r, g, b]
      end.flatten
      bmp_data = pixels.pack("C*")

      # Use distance=3 for RGB (24-bit pixels)
      delta = Omnizip::Filters::Delta.new(3)
      filtered = delta.encode(bmp_data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)

      # Should achieve good compression
      plain_out = StringIO.new
      lzma.compress(StringIO.new(bmp_data), plain_out)
      expect(compressed_out.string.bytesize).to be <
                                                plain_out.string.bytesize

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(bmp_data)
    end

    it "handles 32-bit RGBA image data" do
      # Simulate RGBA pixels
      pixels = (0..255).map do |i|
        [i % 256, (i + 50) % 256, (i + 100) % 256, 255]
      end.flatten
      rgba_data = pixels.pack("C*")

      # Use distance=4 for RGBA (32-bit pixels)
      delta = Omnizip::Filters::Delta.new(4)
      filtered = delta.encode(rgba_data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)

      # Verify round-trip
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)
      expect(restored).to eq(rgba_data)
      expect(restored.unpack("C*")).to eq(pixels)
    end
  end

  describe "edge cases in integration" do
    it "handles empty data through full pipeline" do
      data = ""
      delta = Omnizip::Filters::Delta.new(1)

      filtered = delta.encode(data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)

      expect(restored).to eq(data)
    end

    it "handles very small data through full pipeline" do
      data = "AB"
      delta = Omnizip::Filters::Delta.new(1)

      filtered = delta.encode(data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)
      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)

      expect(restored).to eq(data)
    end

    it "handles large buffers efficiently" do
      # 100KB of data
      data = Array.new(100_000) { |i| (i % 256) }.pack("C*")

      delta = Omnizip::Filters::Delta.new(1)
      filtered = delta.encode(data)
      compressed_out = StringIO.new
      lzma.compress(StringIO.new(filtered), compressed_out)

      decompressed_out = StringIO.new
      lzma.decompress(StringIO.new(compressed_out.string), decompressed_out)
      restored = delta.decode(decompressed_out.string)

      expect(restored).to eq(data)
      expect(restored.bytesize).to eq(100_000)
    end
  end
end
