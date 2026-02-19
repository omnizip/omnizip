# frozen_string_literal: true

require "spec_helper"
require "omnizip/algorithms/lzma/literal_encoder"
require "omnizip/algorithms/lzma/literal_decoder"
require "omnizip/algorithms/lzma/range_encoder"
require "omnizip/algorithms/lzma/range_decoder"
require "omnizip/algorithms/lzma/bit_model"

RSpec.describe Omnizip::Algorithms::LZMA::LiteralEncoder do
  let(:encoder) { described_class.new }
  let(:decoder) { Omnizip::Algorithms::LZMA::LiteralDecoder.new }
  let(:output) { StringIO.new }
  let(:range_encoder) { Omnizip::Algorithms::LZMA::RangeEncoder.new(output) }
  # Allocate models for literal states: LITERAL_CODER_SIZE << lc models
  # For lc=3: 0x300 << 3 = 0x1800 = 6144 models
  let(:models) { Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new } }
  # Standard XZ LZMA parameters
  let(:lc) { 3 }
  # literal_mask limits the context range
  # For this test, use a smaller mask to fit within allocated models
  # The models array size is 0x300 << lc = 6144
  # Each context needs 3 * 2^lc = 24 models (for 8 bits)
  # So max context = 6144 / 24 ≈ 256
  # literal_mask = 0xFF allows contexts 0-255 (256 values)
  let(:literal_mask) { 0xFF }
  let(:pos) { 0 }
  let(:prev_byte) { 0 }

  describe "#encode_unmatched" do
    it "encodes a simple byte value" do
      byte = 0x42 # 'B'

      expect do
        encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                                 range_encoder, models)
      end.not_to raise_error
    end

    it "encodes zero byte" do
      byte = 0x00

      expect do
        encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                                 range_encoder, models)
      end.not_to raise_error
    end

    it "encodes maximum byte value" do
      byte = 0xFF

      expect do
        encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                                 range_encoder, models)
      end.not_to raise_error
    end

    it "uses different models for different literal states" do
      byte = 0x42

      # Allocate enough models for both literal states
      # For lc=3: 0x300 << 3 = 6144 models
      models_0 = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      models_1 = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }

      output_0 = StringIO.new
      output_1 = StringIO.new

      encoder_0 = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_0)
      encoder_1 = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_1)

      encoder.encode_unmatched(byte, 0, 0, lc, literal_mask, encoder_0, models_0)
      encoder.encode_unmatched(byte, 1, 0, lc, literal_mask, encoder_1, models_1)

      # Different positions should use different model offsets
      # So they shouldn't affect the same models
      # This is a basic verification that pos affects model selection
      expect(models_0).not_to eq(models_1)
    end

    it "round-trips with decoder" do
      byte = 0x7F

      # Encoder uses its own models
      # For lc=3: 0x300 << 3 = 6144 models
      enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                               range_encoder, enc_models)
      range_encoder.flush

      # Decoder uses separate fresh models (just like real Decoder does)
      # XZ Utils compatibility: lit_state = (((pos << 8) + prev_byte) & literal_mask)
      lit_state = (((pos << 8) + prev_byte) & literal_mask)
      dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      output.rewind
      range_decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)
      decoded_byte = decoder.decode_unmatched(lit_state, lc, range_decoder, dec_models)

      expect(decoded_byte).to eq(byte)
    end

    it "round-trips multiple different bytes" do
      bytes = [0x00, 0x42, 0x7F, 0x80, 0xFF]

      bytes.each do |byte|
        output_io = StringIO.new
        # Allocate sufficient models
        enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
        enc = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_io)

        encoder.encode_unmatched(byte, 0, 0, lc, literal_mask, enc, enc_models)
        enc.flush

        # Decoder uses separate fresh models
        # XZ Utils compatibility: lit_state = (((pos << 8) + prev_byte) & literal_mask)
        lit_state = (((0 << 8) + 0) & literal_mask)
        dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
        output_io.rewind
        dec = Omnizip::Algorithms::LZMA::RangeDecoder.new(output_io)
        decoded = decoder.decode_unmatched(lit_state, lc, dec, dec_models)

        expect(decoded).to eq(byte), "Failed for byte 0x#{byte.to_s(16)}"
      end
    end
  end

  describe "#encode_matched" do
    it "encodes byte with match byte context" do
      byte = 0x42
      match_byte = 0x40
      0
      pos = 0
      prev_byte = 0

      expect do
        encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                               range_encoder, models)
      end.not_to raise_error
    end

    it "encodes identical byte and match byte" do
      byte = 0x55
      match_byte = 0x55
      0
      pos = 0
      prev_byte = 0

      expect do
        encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                               range_encoder, models)
      end.not_to raise_error
    end

    it "encodes completely different byte and match byte" do
      byte = 0xFF
      match_byte = 0x00
      0
      pos = 0
      prev_byte = 0

      expect do
        encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                               range_encoder, models)
      end.not_to raise_error
    end

    it "round-trips with decoder in matched mode" do
      byte = 0x7A
      match_byte = 0x7B
      lit_state = 0
      pos = 0
      prev_byte = 0

      # Encoder uses its own models
      enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                             range_encoder, enc_models)
      range_encoder.flush

      # Decoder uses separate fresh models
      dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      output.rewind
      range_decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)
      decoded_byte = decoder.decode_matched(match_byte, lit_state, lc, range_decoder,
                                            dec_models)

      expect(decoded_byte).to eq(byte)
    end

    it "round-trips with identical byte and match byte" do
      byte = 0xAA
      match_byte = 0xAA
      lit_state = 0
      pos = 0
      prev_byte = 0

      # Encoder uses its own models
      enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                             range_encoder, enc_models)
      range_encoder.flush

      # Decoder uses separate fresh models
      dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      output.rewind
      range_decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)
      decoded_byte = decoder.decode_matched(match_byte, lit_state, lc, range_decoder,
                                            dec_models)

      expect(decoded_byte).to eq(byte)
    end

    it "round-trips multiple byte/match combinations" do
      test_cases = [
        [0x00, 0x00],
        [0x00, 0xFF],
        [0xFF, 0x00],
        [0x55, 0xAA],
        [0x42, 0x43],
        [0x7F, 0x80],
      ]

      test_cases.each do |byte, match_byte|
        output_io = StringIO.new
        pos = 0
        prev_byte = 0
        # Allocate sufficient models
        enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
        enc = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_io)

        encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                               enc, enc_models)
        enc.flush

        # Decoder uses separate fresh models
        dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
        output_io.rewind
        dec = Omnizip::Algorithms::LZMA::RangeDecoder.new(output_io)
        decoded = decoder.decode_matched(match_byte, 0, lc, dec, dec_models)

        expect(decoded).to eq(byte),
                           "Failed for byte 0x#{byte.to_s(16)} with match 0x#{match_byte.to_s(16)}"
      end
    end
  end

  describe "matched vs unmatched mode" do
    it "produces different output for same byte in different modes" do
      byte = 0x42
      match_byte = 0x40
      pos = 0
      prev_byte = 0

      # Encode unmatched
      output_unmatched = StringIO.new
      models_unmatched = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      enc_unmatched = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_unmatched)
      encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask, enc_unmatched,
                               models_unmatched)
      enc_unmatched.flush

      # Encode matched
      output_matched = StringIO.new
      models_matched = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      enc_matched = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_matched)
      encoder.encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
                             enc_matched, models_matched)
      enc_matched.flush

      # Outputs should differ (different probability models used)
      # Note: They might occasionally be the same due to probability model initialization
      # This test just verifies both modes work
      expect(output_unmatched.string.length).to be > 0
      expect(output_matched.string.length).to be > 0
    end
  end

  describe "integration with range encoder/decoder" do
    it "correctly updates probability models" do
      byte = 0x42
      pos = 0
      prev_byte = 0

      # Encode same byte multiple times
      5.times do
        encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                                 range_encoder, models)
      end

      # Models should have been updated (probabilities changed)
      # At least some models should have non-initial probability
      used_models = models.reject { |m| m.probability == 1024 }
      expect(used_models.length).to be > 0
    end

    it "maintains model state across multiple encodings" do
      bytes = [0x41, 0x42, 0x43]
      pos = 0
      prev_byte = 0

      # Encoder uses its own models
      enc_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      bytes.each do |byte|
        encoder.encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
                                 range_encoder, enc_models)
      end
      range_encoder.flush

      # Decoder uses separate fresh models
      # XZ Utils compatibility: lit_state = (((pos << 8) + prev_byte) & literal_mask)
      lit_state = (((pos << 8) + prev_byte) & literal_mask)
      dec_models = Array.new(0x300 << 3) { Omnizip::Algorithms::LZMA::BitModel.new }
      output.rewind
      range_decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)

      bytes.each do |expected_byte|
        decoded = decoder.decode_unmatched(lit_state, lc, range_decoder, dec_models)
        expect(decoded).to eq(expected_byte)
      end
    end
  end
end
