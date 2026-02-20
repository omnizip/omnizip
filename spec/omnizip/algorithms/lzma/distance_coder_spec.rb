# frozen_string_literal: true

require "spec_helper"
require "omnizip/algorithms/lzma"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA::DistanceCoder do
  let(:num_len_to_pos_states) { 4 }
  let(:coder) { described_class.new(num_len_to_pos_states) }

  describe "#encode and #decode" do
    it "encodes and decodes small distances (0-3)" do
      (0..3).each do |distance|
        test_round_trip(distance, 0)
      end
    end

    it "encodes and decodes medium distances (4-127)" do
      [4, 10, 20, 50, 100, 127].each do |distance|
        test_round_trip(distance, 0)
      end
    end

    it "encodes and decodes large distances (128+)" do
      [128, 256, 512, 1024, 4096, 16384, 65535].each do |distance|
        test_round_trip(distance, 0)
      end
    end

    it "works with different length states" do
      [0, 1, 2, 3].each do |len_state|
        test_round_trip(100, len_state)
      end
    end

    it "handles maximum practical distance" do
      # Test with 64KB-1 (typical dictionary size)
      test_round_trip(65535, 0)
    end

    it "handles very large distances" do
      # Test with larger distances for bigger dictionary sizes
      [0x10000, 0x20000, 0x100000].each do |distance|
        test_round_trip(distance, 0)
      end
    end
  end

  describe "distance slots 0-3 (direct encoding)" do
    # Slots 0-3: distance = slot, no extra bits
    it "round-trips slot 0 (distance 0)" do
      test_round_trip(0, 0)
    end

    it "round-trips slot 1 (distance 1)" do
      test_round_trip(1, 0)
    end

    it "round-trips slot 2 (distance 2)" do
      test_round_trip(2, 0)
    end

    it "round-trips slot 3 (distance 3)" do
      test_round_trip(3, 0)
    end
  end

  describe "distance slots 4-13 (position model encoding)" do
    # Slots 4-13: Use dist_special probability models
    # Slot 4: distances 4-5
    # Slot 5: distances 6-7
    # Slot 6: distances 8-11
    # ...
    # Slot 13: distances 64-127

    it "round-trips slot 4 boundaries (distances 4-5)" do
      test_round_trip(4, 0)
      test_round_trip(5, 0)
    end

    it "round-trips slot 6 boundaries (distances 8-11)" do
      test_round_trip(8, 0)
      test_round_trip(11, 0)
    end

    it "round-trips slot 10 mid-range (distances 32-63)" do
      test_round_trip(32, 0)
      test_round_trip(48, 0)
      test_round_trip(63, 0)
    end

    it "round-trips slot 13 boundaries (distances 64-127)" do
      test_round_trip(64, 0)
      test_round_trip(100, 0)
      test_round_trip(127, 0)
    end
  end

  describe "distance slots 14+ (direct bits + aligned bits)" do
    # Slots 14+: Use rc_direct for high bits + align encoder for low 4 bits
    # Slot 14: distances 128-159 (2^7 to 2^7+31)
    # Slot 15: distances 160-191
    # Slot 16: distances 192-255
    # ...
    # Slot 63: maximum distance

    it "round-trips slot 14 (distances 128-159)" do
      test_round_trip(128, 0)
      test_round_trip(144, 0)
      test_round_trip(159, 0)
    end

    it "round-trips slot 15 (distances 160-191)" do
      test_round_trip(160, 0)
      test_round_trip(175, 0)
      test_round_trip(191, 0)
    end

    it "round-trips slot 20 (distances 512-575)" do
      test_round_trip(512, 0)
      test_round_trip(544, 0)
      test_round_trip(575, 0)
    end

    it "round-trips slot 30 (distances 8192-9215)" do
      test_round_trip(8192, 0)
      test_round_trip(8704, 0)
      test_round_trip(9215, 0)
    end

    it "round-trips slot 40 (distances 131072-147455)" do
      test_round_trip(131_072, 0)
      test_round_trip(139_264, 0)
      test_round_trip(147_455, 0)
    end

    it "round-trips very high slots (50+)" do
      # Slot 50: ~2^25 range
      test_round_trip(33_554_432, 0)
      test_round_trip(33_554_448, 0)
    end
  end

  describe "edge cases at slot boundaries" do
    # Test exact boundary distances where slot transitions occur
    it "round-trips slot 3 to 4 boundary (distances 3, 4)" do
      test_round_trip(3, 0)
      test_round_trip(4, 0)
    end

    it "round-trips slot 13 to 14 boundary (distances 127, 128)" do
      test_round_trip(127, 0)
      test_round_trip(128, 0)
    end

    it "round-trips power-of-2 boundaries" do
      # These are where slot transitions happen
      [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
       65536].each do |dist|
        test_round_trip(dist, 0)
        test_round_trip(dist - 1, 0)
      end
    end
  end

  describe "all distance slots comprehensive" do
    # Test representative distance for each slot 0-63
    (0..63).each do |slot|
      it "round-trips distance for slot #{slot}" do
        # Calculate a representative distance for this slot
        distance = if slot < 4
                     slot
                   elsif slot < 14
                     # Slots 4-13: base + some offset
                     footer_bits = (slot >> 1) - 1
                     base = (2 | (slot & 1)) << footer_bits
                     base + (1 << (footer_bits - 1)) # middle of range
                   else
                     # Slots 14+: base + offset with aligned bits
                     footer_bits = (slot >> 1) - 1
                     base = (2 | (slot & 1)) << footer_bits
                     base + 0x55 # Some aligned pattern
                   end
        test_round_trip(distance, 0)
      end
    end
  end

  describe "distance slot calculation" do
    it "calculates slots correctly for small distances" do
      coder = described_class.new(num_len_to_pos_states)

      # Slots 0-3 should be distances 0-3
      expect(coder.send(:get_dist_slot, 0)).to eq(0)
      expect(coder.send(:get_dist_slot, 1)).to eq(1)
      expect(coder.send(:get_dist_slot, 2)).to eq(2)
      expect(coder.send(:get_dist_slot, 3)).to eq(3)
    end

    it "calculates slots correctly for medium distances" do
      coder = described_class.new(num_len_to_pos_states)

      # Slot 4: distances 4-5
      expect(coder.send(:get_dist_slot, 4)).to eq(4)
      expect(coder.send(:get_dist_slot, 5)).to eq(4)

      # Slot 5: distances 6-7
      expect(coder.send(:get_dist_slot, 6)).to eq(5)
      expect(coder.send(:get_dist_slot, 7)).to eq(5)

      # Slot 6: distances 8-11
      expect(coder.send(:get_dist_slot, 8)).to eq(6)
      expect(coder.send(:get_dist_slot, 11)).to eq(6)

      # Slot 7: distances 12-15
      expect(coder.send(:get_dist_slot, 12)).to eq(7)
      expect(coder.send(:get_dist_slot, 15)).to eq(7)

      # Higher slots
      expect(coder.send(:get_dist_slot, 128)).to be >= 14
    end
  end

  def test_round_trip(distance, len_state)
    output = StringIO.new
    encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)
    encode_coder = described_class.new(num_len_to_pos_states)

    # Encode
    encode_coder.encode(encoder, distance, len_state)
    encoder.flush

    # Decode
    output.rewind
    decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)
    decode_coder = described_class.new(num_len_to_pos_states)
    decoded_distance = decode_coder.decode(decoder, len_state)

    expect(decoded_distance).to eq(distance),
                                "Distance #{distance} with len_state #{len_state} failed round-trip"
  end
end
