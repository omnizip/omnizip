# frozen_string_literal: true

require "spec_helper"
require "omnizip/algorithms/lzma"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA::LengthCoder do
  let(:num_pos_states) { 4 } # 1 << pb where pb = 2
  let(:coder) { described_class.new(num_pos_states) }
  let(:output) { StringIO.new }
  let(:encoder) { Omnizip::Algorithms::LZMA::RangeEncoder.new(output) }

  describe "#encode and #decode" do
    it "encodes and decodes low lengths (0-7)" do
      (0..7).each do |length|
        test_round_trip(length, 0)
      end
    end

    it "encodes and decodes mid lengths (8-15)" do
      (8..15).each do |length|
        test_round_trip(length, 0)
      end
    end

    it "encodes and decodes high lengths (16-271)" do
      [16, 50, 100, 150, 200, 250, 271].each do |length|
        test_round_trip(length, 0)
      end
    end

    it "works with different position states" do
      [0, 1, 2, 3].each do |pos_state|
        test_round_trip(10, pos_state)
      end
    end

    it "handles maximum length (271)" do
      max_length = Omnizip::Algorithms::LZMA::Constants::MATCH_LEN_MAX -
        Omnizip::Algorithms::LZMA::Constants::MATCH_LEN_MIN
      test_round_trip(max_length, 0)
    end
  end

  def test_round_trip(length, pos_state)
    output = StringIO.new
    encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)
    encode_coder = described_class.new(num_pos_states)

    # Encode
    encode_coder.encode(encoder, length, pos_state)
    encoder.flush

    # Decode
    output.rewind
    decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(output)
    decode_coder = described_class.new(num_pos_states)
    decoded_length = decode_coder.decode(decoder, pos_state)

    expect(decoded_length).to eq(length),
                              "Length #{length} with pos_state #{pos_state} failed round-trip"
  end
end
