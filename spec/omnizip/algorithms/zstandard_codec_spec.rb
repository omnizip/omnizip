# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "fileutils"

RSpec.describe Omnizip::Algorithms::Zstandard do
  let(:has_zstd_cli) { system("which zstd > /dev/null 2>&1") }

  describe "XXHash64" do
    it "matches reference vectors" do
      h = described_class::XXHash64
      expect(h.digest("").to_s(16)).to eq("ef46db3751d8e999")
      expect(h.digest("a").to_s(16)).to eq("d24ec4f1a98c6e5b")
      expect(h.digest("abc").to_s(16)).to eq("44bc2cf5ad770999")
    end

    it "computes the zstd frame checksum as low 32 bits of XXH64" do
      # Golden vector: 1 MiB of zeros decodes with checksum 0xE1163EF1
      # (zstd golden-decompression rle-first-block.zst).
      h = described_class::XXHash64
      expect(h.frame_checksum("\0" * 1_048_576)).to eq(0xE1163EF1)
    end
  end

  describe "FSE reverse bitstream" do
    it "reads bytes from the end, MSB first, skipping the end mark" do
      bs = described_class::FSE::BitStream.new([0xFF].pack("C"))
      7.times { expect(bs.read_bits(1)).to eq(1) }
    end

    it "assembles multi-bit reads with the first bit as MSB" do
      # Last byte 0xC0: end mark is bit 7; the next four bits (6..3)
      # are 1000, so a 4-bit read yields 0b1000 (MSB = first bit read).
      bs = described_class::FSE::BitStream.new([0x00, 0xC0].pack("C*"))
      expect(bs.read_bits(4)).to eq(0b1000)
    end

    it "peeks without consuming" do
      bs = described_class::FSE::BitStream.new([0xAB, 0xCD].pack("C*"))
      expect(bs.peek_bits(4)).to eq(bs.peek_bits(4))
    end
  end

  describe "FSE decode table" do
    it "matches the RFC 8878 Appendix A literal-length table" do
      table = described_class::FSE::Table.build_predefined(
        described_class::Constants::PREDEFINED_LL_DISTRIBUTION.to_a, 6
      )

      # Spot-checked rows from Appendix A (state, symbol, nbBits, base).
      expect(row(table, 0)).to eq([0, 4, 0])
      expect(row(table, 1)).to eq([0, 4, 16])
      expect(row(table, 2)).to eq([1, 5, 32])
      expect(row(table, 22)).to eq([0, 4, 32])
      expect(row(table, 63)).to eq([32, 6, 0])
    end

    it "matches the RFC 8878 Appendix A offset table" do
      table = described_class::FSE::Table.build_predefined(
        described_class::Constants::PREDEFINED_OFFSET_DISTRIBUTION.to_a, 5
      )

      expect(row(table, 0)).to eq([0, 5, 0])
      expect(row(table, 1)).to eq([6, 4, 0])
      expect(row(table, 27)).to eq([28, 5, 0])
      expect(row(table, 31)).to eq([24, 5, 0])
    end

    it "matches the RFC 8878 Appendix A match-length table" do
      table = described_class::FSE::Table.build_predefined(
        described_class::Constants::PREDEFINED_ML_DISTRIBUTION.to_a, 6
      )

      expect(row(table, 0)).to eq([0, 6, 0])
      expect(row(table, 57)).to eq([52, 6, 0])
      expect(row(table, 63)).to eq([46, 6, 0])
    end

    def row(table, state)
      e = table[state]
      [e.symbol, e.num_bits, e.baseline]
    end
  end

  describe "FSE table description + interleaved weights decode" do
    # Payload extracted from zstd v1.5.7 output (tree byte 0x1e = 30
    # bytes of FSE data), with the 255 decoded weights captured from
    # the C reference HUF_readStats.
    let(:header) do
      [0x1e, 0x10, 0xd8, 0xda, 0x72, 0x0c, 0x03, 0xb8, 0xa2, 0x61, 0x70,
       0x4d, 0x92, 0x3a, 0x91, 0x6e, 0xa1, 0x26, 0x12, 0xd9, 0x6e, 0xa1,
       0xa5, 0x95, 0xed, 0x16, 0x35, 0x0c, 0x53, 0x91, 0x02].pack("C*")
    end

    let(:expected_weights) do
      # Cross-validated against real zstd output: the 8 at index 0 and
      # the 2s at 142/195/212 match the C reference capture exactly; a
      # one-symbol shift anywhere would garble every wide-alphabet
      # file in the interop suite.
      base = Array.new(255, 1)
      base[0] = 8
      block_vals = [3, 3, 4, 3, 3, 4, 4, 4, 3, 4, 3, 4, 3, 3, 4, 4, 4,
                    3, 3, 3, 3, 4, 3, 3, 4, 4]
      block_vals.each_with_index { |v, i| base[65 + i] = v }
      base[142] = 2
      base[195] = 2
      base[212] = 2
      base
    end

    it "decodes the exact weight sequence the C reference produces" do
      fse = described_class::FSE
      table, consumed = fse.read_table(header.byteslice(1..))
      weights = fse.decode_stream(table, header.byteslice((1 + consumed)..), 255)

      expect(weights).to eq(expected_weights)
    end
  end

  describe "FSE encoder round trip" do
    it "round-trips NCount and bitstream through the decoder" do
      fse = described_class::FSE
      rng = Random.new(4242)
      symbols = Array.new(500) { |_i| [1, 2, 3, 1, 2, 4, 1][rng.rand(7)] }

      encoder = fse::Encoder.build_from_symbols(symbols, 11, 6)
      expect(encoder).not_to be_nil

      payload = encoder.compress(symbols)
      table, consumed = fse.read_table(payload)
      decoded = fse.decode_stream(table, payload.byteslice(consumed..),
                                  symbols.length + 8)

      expect(decoded).to eq(symbols)
    end
  end

  describe "Huffman weights" do
    it "derives the implied last weight from the Kraft inequality" do
      reader = described_class::HuffmanTableReader
      expect(reader.implied_last_weight([1, 2])).to eq(1)
      expect(reader.implied_last_weight([3, 1, 2])).to eq(1)
    end

    it "rejects a remainder that is not a power of two" do
      reader = described_class::HuffmanTableReader
      expect { reader.implied_last_weight([1, 3]) }.to raise_error(
        Omnizip::DecompressionError,
      )
    end

    it "reads direct weights" do
      table, consumed = described_class::HuffmanTableReader.read(
        [0x81, 0x11].pack("C*"),
      )
      expect(consumed).to eq(2)
      expect(table.weights).to eq([1, 1, 2])
    end
  end

  describe "frame header window size" do
    it "applies the /8 mantissa from RFC 8878 §3.1.1.1.2" do
      # Exponent 8, mantissa 0: wl 18 -> 262144.
      header = window_header(0x40)
      expect(header.window_log).to eq(18)
      expect(header.window_size).to eq(262_144)
    end

    it "includes the mantissa term" do
      # Exponent 8, mantissa 5: 262144 + (262144/8)*5 = 425984.
      header = window_header(0x45)
      expect(header.window_size).to eq(425_984)
    end

    def window_header(byte)
      # Descriptor 0x00: no single-segment flag, no FCS; the next byte
      # is the window descriptor under test.
      described_class::Frame::Header.parse_from(
        [0x00, byte].pack("C*"), 0
      ).first
    end
  end

  describe "literals section headers" do
    it "round-trips raw literals across size-format boundaries" do
      enc = described_class::LiteralsEncoder
      dec = described_class::LiteralsDecoder

      [31, 32, 4095, 4096].each do |size|
        data = Random.new(size).bytes(size)
        section = enc.encode_raw(data)
        result = dec.decode(section)
        expect(result.literals).to eq(data)
        expect(result.consumed).to eq(section.bytesize)
      end
    end

    it "round-trips RLE literals" do
      enc = described_class::LiteralsEncoder
      dec = described_class::LiteralsDecoder

      [5, 100, 5000].each do |size|
        data = "q" * size
        section = enc.encode_rle(data)
        result = dec.decode(section)
        expect(result.literals).to eq(data)
      end
    end
  end

  describe "compressed literals round trip" do
    it "encodes and decodes Huffman literals" do
      enc = described_class::HuffmanEncoder
      dec = described_class::LiteralsDecoder

      rng = Random.new(31)
      words = %w[lorem ipsum dolor sit amet]
      [1_000, 5_000, 30_000].each do |size|
        data = Array.new(size) { words[rng.rand(words.length)] }
          .join(" ")
        section = enc.encode_literals(data)
        result = dec.decode(section)
        expect(result.literals).to eq(data)
        expect(result.consumed).to eq(section.bytesize)
      end
    end
  end

  describe "encoder (issue #27)" do
    let(:text) do
      rng = Random.new(7)
      words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit]
      Array.new(5_000) { words[rng.rand(words.size)] }.join(" ")
    end

    it "compresses compressible data below its input size" do
      compressed = described_class.compress(text)
      expect(compressed.bytesize).to be < text.bytesize
    end

    it "round-trips through the decoder" do
      compressed = described_class.compress(text)
      expect(described_class.decompress(compressed)).to eq(text)
    end

    it "round-trips data spanning multiple 128 KiB blocks" do
      data = text * 8
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end

    it "round-trips incompressible data via raw blocks" do
      data = Random.new(99).bytes(50_000)
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end

    it "round-trips checksummed frames" do
      compressed = described_class.compress(text, checksum: true)
      expect(described_class.decompress(compressed)).to eq(text)
    end
  end

  describe "sequence encoding (match finder + FSE sequences)" do
    let(:text) do
      rng = Random.new(7)
      words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit]
      Array.new(20_000) { words[rng.rand(words.size)] }.join(" ")
    end

    it "beats Huffman-only ratios on text (matches are encoded)" do
      compressed = described_class.compress(text)
      # Huffman literals alone bottom out near 0.49 on this corpus;
      # sequence encoding brings it below 0.30, and the greedy path's
      # rep0 fast-path + backward extension bring it under 0.17
      # (reference zstd -3: 0.136).
      expect(compressed.bytesize.to_f / text.bytesize).to be < 0.17
    end

    it "round-trips across levels through our decoder" do
      [1, 3, 9, 19].each do |level|
        compressed = described_class.compress(text, level: level)
        expect(described_class.decompress(compressed)).to eq(text)
      end
    end

    it "round-trips alternating structured and random regions" do
      rng = Random.new(7)
      data = ("abc" * 100) + rng.bytes(500) + ("abc" * 200)
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end

    it "round-trips long single-pattern runs" do
      data = "abcabcabcabcabcabc " * 20
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end

    it "round-trips skewed binary literals with wide alphabets" do
      rng = Random.new(5)
      data = Array.new(30_000) do |i|
        i % 10 < 7 ? 0 : rng.rand(255) + 1
      end.pack("C*")
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end

    it "carries wire repeat-offset state correctly between blocks" do
      # Two blocks: the second reuses matches from the first across
      # the 128 KiB boundary; a corrupted rep hand-off garbles it.
      data = text * 8
      compressed = described_class.compress(data)
      expect(described_class.decompress(compressed)).to eq(data)
    end
  end

  describe "LDM (long-distance matching)" do
    it "finds a match at a 50 KB distance through the sparse table" do
      data = "\0" * 100_000
      pattern = (0...256).map { |i| i % 251 }.pack("C*")
      data[0, 256] = pattern
      data[50_000, 256] = pattern

      ldm = described_class::LdmHashTable.new(100_000, 20, 64)
      (0...data.bytesize).each { |pos| ldm.insert(data, pos) }

      match = ldm.find_match(data, 50_000, 0xFFFFFFFF, 4, 100_000)
      expect(match).not_to be_nil
      expect(match[0]).to eq(50_000)
      expect(match[1]).to be >= 200
    end

    it "rarely matches pseudo-random data" do
      data = (0...10_000).map { |i| ((i * 2_654_435_761) >> 16) & 0xFF }
        .pack("C*")
      ldm = described_class::LdmHashTable.new(10_000, 16, 64)
      (0...data.bytesize).each { |pos| ldm.insert(data, pos) }

      matches = (0...data.bytesize).count do |pos|
        !ldm.find_match(data, pos, 0xFFFFFFFF, 4, 10_000).nil?
      end
      expect(matches).to be < data.bytesize / 10
    end

    it "round-trips multi-block data at LDM levels" do
      # Over one block: LDM is engaged at levels >= 19 and must
      # still produce decodable frames (cross-block long matches).
      data = ("lorem ipsum dolor sit amet " * 6_000) +
        ("x" * 5_000) + ("lorem ipsum dolor sit amet " * 6_000)
      [19, 22].each do |level|
        compressed = described_class.compress(data, level: level)
        expect(described_class.decompress(compressed)).to eq(data)
      end
    end

    it "beats the non-LDM ratio on repeated far-apart content" do
      # The same paragraph repeated with a block of random noise in
      # between: only long-distance matching can tie the copies
      # together across the 128 KiB block boundary.
      rng = Random.new(11)
      paragraph = ("sed do eiusmod tempor incididunt " * 2_500)
      data = paragraph + rng.bytes(70_000) + paragraph
      low = described_class.compress(data, level: 3)
      high = described_class.compress(data, level: 19)
      expect(high.bytesize).to be < low.bytesize
    end
  end

  describe "encoder interop with the zstd CLI" do
    before { skip "zstd CLI not available" unless has_zstd_cli }

    let(:text) do
      rng = Random.new(7)
      words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit]
      Array.new(20_000) { words[rng.rand(words.size)] }.join(" ")
    end

    it "produces frames the system decoder accepts at several levels" do
      [1, 3, 9, 19].each do |level|
        compressed = described_class.compress(text, level: level)
        path = "/tmp/omnizip_zenc_interop.zst"
        File.binwrite(path, compressed)
        system("zstd -d -q -f #{path} -o #{path}.out")
        expect(File.binread("#{path}.out")).to eq(text)
      end
    ensure
      FileUtils.rm_f("/tmp/omnizip_zenc_interop.zst")
      FileUtils.rm_f("/tmp/omnizip_zenc_interop.zst.out")
    end
  end

  describe "decoder interop with the zstd CLI" do
    before { skip "zstd CLI not available" unless has_zstd_cli }

    it "decodes frames produced by system zstd at several levels" do
      rng = Random.new(7)
      words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit sed
                 do eiusmod tempor incididunt ut labore]
      data = Array.new(20_000) { words[rng.rand(words.size)] }.join(" ")
      path = "/tmp/omnizip_zstd_interop.bin"
      File.binwrite(path, data)

      [1, 3, 9, 19].each do |level|
        system("zstd -#{level} -q -f #{path} -o #{path}.zst")
        compressed = File.binread("#{path}.zst")
        decoder = described_class::Decoder.new(StringIO.new(compressed))
        expect(decoder.decode_stream).to eq(data)
      end
    ensure
      FileUtils.rm_f(path)
      FileUtils.rm_f("#{path}.zst")
    end
  end
end
