# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe "LZMA Range Coding" do
  describe Omnizip::Algorithms::LZMA::BitModel do
    let(:model) { described_class.new }

    describe "#initialize" do
      it "initializes with default probability" do
        expect(model.probability).to eq(
          Omnizip::Algorithms::LZMA::Constants::INIT_PROBS
        )
      end

      it "initializes with custom probability" do
        custom_model = described_class.new(1000)
        expect(custom_model.probability).to eq(1000)
      end
    end

    describe "#update" do
      it "updates probability for bit 0" do
        initial_prob = model.probability
        model.update(0)
        expect(model.probability).to be > initial_prob
      end

      it "updates probability for bit 1" do
        initial_prob = model.probability
        model.update(1)
        expect(model.probability).to be < initial_prob
      end
    end

    describe "#prob_0 and #prob_1" do
      it "returns complementary probabilities" do
        total = Omnizip::Algorithms::LZMA::Constants::BIT_MODEL_TOTAL
        expect(model.prob_0 + model.prob_1).to eq(total)
      end
    end
  end

  describe "Range Encoder/Decoder Round-Trip" do
    let(:encoder_output) { StringIO.new }
    let(:encoder) do
      Omnizip::Algorithms::LZMA::RangeEncoder.new(encoder_output)
    end

    describe "encoding and decoding single bits" do
      it "correctly encodes and decodes a sequence of bits" do
        bits = [0, 1, 0, 0, 1, 1, 0, 1]
        model = Omnizip::Algorithms::LZMA::BitModel.new

        # Encode
        bits.each { |bit| encoder.encode_bit(model, bit) }
        encoder.flush

        # Decode
        encoder_output.rewind
        decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(
          encoder_output
        )
        decode_model = Omnizip::Algorithms::LZMA::BitModel.new
        decoded_bits = bits.map { decoder.decode_bit(decode_model) }

        expect(decoded_bits).to eq(bits)
      end
    end

    describe "encoding and decoding direct bits" do
      it "correctly encodes and decodes values" do
        values = [5, 15, 255, 127, 0]
        num_bits = 8

        # Encode
        values.each { |value| encoder.encode_direct_bits(value, num_bits) }
        encoder.flush

        # Decode
        encoder_output.rewind
        decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(
          encoder_output
        )
        decoded_values = values.map do
          decoder.decode_direct_bits(num_bits)
        end

        expect(decoded_values).to eq(values)
      end

      it "handles different bit lengths" do
        test_cases = [
          { value: 3, bits: 2 },
          { value: 7, bits: 3 },
          { value: 15, bits: 4 },
          { value: 31, bits: 5 }
        ]

        # Encode
        test_cases.each do |tc|
          encoder.encode_direct_bits(tc[:value], tc[:bits])
        end
        encoder.flush

        # Decode
        encoder_output.rewind
        decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(
          encoder_output
        )
        decoded_values = test_cases.map do |tc|
          decoder.decode_direct_bits(tc[:bits])
        end

        expected = test_cases.map { |tc| tc[:value] }
        expect(decoded_values).to eq(expected)
      end
    end

    describe "mixed encoding and decoding" do
      it "correctly handles bits and direct values together" do
        bits = [0, 1, 1, 0]
        value = 42
        more_bits = [1, 0, 1]

        model = Omnizip::Algorithms::LZMA::BitModel.new

        # Encode
        bits.each { |bit| encoder.encode_bit(model, bit) }
        encoder.encode_direct_bits(value, 8)
        more_bits.each { |bit| encoder.encode_bit(model, bit) }
        encoder.flush

        # Decode
        encoder_output.rewind
        decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(
          encoder_output
        )
        decode_model = Omnizip::Algorithms::LZMA::BitModel.new

        decoded_bits = bits.map { decoder.decode_bit(decode_model) }
        decoded_value = decoder.decode_direct_bits(8)
        decoded_more = more_bits.map { decoder.decode_bit(decode_model) }

        expect(decoded_bits).to eq(bits)
        expect(decoded_value).to eq(value)
        expect(decoded_more).to eq(more_bits)
      end
    end
  end

  describe Omnizip::Algorithms::LZMA do
    describe ".metadata" do
      let(:metadata) { described_class.metadata }

      it "returns algorithm metadata" do
        expect(metadata).to be_a(
          Omnizip::Models::AlgorithmMetadata
        )
      end

      it "has correct name" do
        expect(metadata.name).to eq("lzma")
      end

      it "has description" do
        expect(metadata.description).to include("LZMA")
      end

      it "has version" do
        expect(metadata.version).to match(/\d+\.\d+\.\d+/)
      end
    end

    describe "#compress and #decompress" do
      let(:algorithm) { described_class.new }
      let(:input) { StringIO.new("test data") }
      let(:output) { StringIO.new }

      it "successfully compresses data" do
        input = StringIO.new("test")
        output = StringIO.new

        expect { algorithm.compress(input, output) }.not_to raise_error
      end

      it "successfully decompresses valid data" do
        # First compress some data
        input = StringIO.new("test")
        compressed = StringIO.new
        algorithm.compress(input, compressed)
        compressed.rewind

        # Then decompress it
        output = StringIO.new
        expect { algorithm.decompress(compressed, output) }.not_to raise_error
      end
    end
  end
end
