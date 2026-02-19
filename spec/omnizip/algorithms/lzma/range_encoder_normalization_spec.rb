# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/omnizip/algorithms/lzma/range_encoder"
require_relative "../../../../lib/omnizip/algorithms/lzma/xz_buffered_range_encoder"
require_relative "../../../../lib/omnizip/algorithms/lzma/bit_model"

RSpec.describe "Range Encoder Normalization" do
  describe "RangeEncoder#shift_low (normalization)" do
    it "handles normalization without crashing" do
      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)

      # Encode many bits to trigger normalization
      # Each bit encoding may trigger normalization
      prob_model = Omnizip::Algorithms::LZMA::BitModel.new(0x400)

      100.times do |i|
        encoder.encode_bit(prob_model, i % 2)
      end

      encoder.flush

      # Should produce output without error
      expect(output.string.bytesize).to be > 0
    end

    it "produces consistent output for same inputs" do
      output1 = StringIO.new
      output2 = StringIO.new

      encoder1 = Omnizip::Algorithms::LZMA::RangeEncoder.new(output1)
      encoder2 = Omnizip::Algorithms::LZMA::RangeEncoder.new(output2)

      prob_model = Omnizip::Algorithms::LZMA::BitModel.new(0x400)

      10.times do
        encoder1.encode_bit(prob_model, 0)
        encoder2.encode_bit(prob_model, 0)
      end

      encoder1.flush
      encoder2.flush

      expect(output1.string).to eq(output2.string)
    end

    it "produces consistent output across multiple runs" do
      outputs = []
      5.times do
        output = StringIO.new
        encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)

        prob_model = Omnizip::Algorithms::LZMA::BitModel.new(0x400)

        10.times do |i|
          encoder.encode_bit(prob_model, i % 2)
        end

        encoder.flush
        outputs << output.string
      end

      # All outputs should be identical
      expect(outputs.uniq.size).to eq(1)
    end
  end

  describe "XzBufferedRangeEncoder#shift_low_buffered (normalization)" do
    it "handles normalization without crashing" do
      # Pre-allocate output buffer with null bytes
      output = "\x00" * 1000
      out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)
      out_size = 1000

      encoder = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(StringIO.new)

      # Queue bits to trigger normalization (max 53 symbols)
      prob_model = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)

      40.times do |i|
        encoder.queue_bit(prob_model, i % 2)
        # Encode periodically to avoid buffer overflow
        encoder.encode_symbols(output, out_pos, out_size) if i % 10 == 9
      end

      encoder.queue_flush
      encoder.encode_symbols(output, out_pos, out_size)

      # Should produce output without error
      expect(out_pos.value).to be > 0
    end

    it "produces consistent output for same inputs" do
      output1 = "\x00" * 1000
      output2 = "\x00" * 1000
      out_pos1 = Omnizip::Algorithms::LZMA::IntRef.new(0)
      out_pos2 = Omnizip::Algorithms::LZMA::IntRef.new(0)
      out_size = 1000

      encoder1 = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(StringIO.new)
      encoder2 = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(StringIO.new)

      prob_model1 = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)
      prob_model2 = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)

      10.times do
        encoder1.queue_bit(prob_model1, 0)
        encoder2.queue_bit(prob_model2, 0)
      end

      encoder1.queue_flush
      encoder2.queue_flush

      encoder1.encode_symbols(output1, out_pos1, out_size)
      encoder2.encode_symbols(output2, out_pos2, out_size)

      expect(output1.bytes[0...out_pos1.value]).to eq(output2.bytes[0...out_pos2.value])
    end

    it "produces consistent output across multiple runs" do
      outputs = []
      out_size = 1000

      5.times do
        output = "\x00" * 1000
        out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)

        encoder = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(StringIO.new)

        prob_model = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)

        10.times do |i|
          encoder.queue_bit(prob_model, i % 2)
        end

        encoder.queue_flush
        encoder.encode_symbols(output, out_pos, out_size)

        outputs << output.bytes[0...out_pos.value]
      end

      # All outputs should be identical
      expect(outputs.uniq.size).to eq(1)
    end
  end

  describe "RangeEncoder vs XzBufferedRangeEncoder consistency" do
    it "produces identical output for same bit sequence" do
      # Create identical encoders
      output_re = StringIO.new
      output_buf = "\x00" * 1000
      out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)

      encoder_re = Omnizip::Algorithms::LZMA::RangeEncoder.new(output_re)
      encoder_buf = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(StringIO.new)

      # Encode same bit sequence
      prob_re = Omnizip::Algorithms::LZMA::BitModel.new(0x400)
      prob_buf = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)

      10.times do |i|
        encoder_re.encode_bit(prob_re, i % 2)
        encoder_buf.queue_bit(prob_buf, i % 2)
      end

      encoder_re.flush
      encoder_buf.queue_flush
      encoder_buf.encode_symbols(output_buf, out_pos, 1000)

      # Extract bytes
      bytes_re = output_re.string.bytes
      bytes_buf = output_buf.bytes[0...out_pos.value]

      # They should produce identical output
      expect(bytes_re).to eq(bytes_buf)
    end
  end

  describe "Normalization edge cases" do
    it "handles carry propagation correctly" do
      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)

      # Encode bits that will cause low to exceed 32 bits and require carry
      prob = Omnizip::Algorithms::LZMA::BitModel.new(0x400)

      # All 1s will cause low to accumulate quickly
      50.times do
        encoder.encode_bit(prob, 1)
      end

      encoder.flush

      expect(output.string.bytesize).to be > 0
    end

    it "handles cache_size correctly during multiple normalizations" do
      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)

      prob = Omnizip::Algorithms::LZMA::BitModel.new(0x400)

      200.times do |i|
        encoder.encode_bit(prob, i % 2)
      end

      encoder.flush

      # Should have many output bytes
      expect(output.string.bytesize).to be > 10
    end
  end
end
