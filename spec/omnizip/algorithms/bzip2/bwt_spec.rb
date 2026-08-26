# frozen_string_literal: true

require "spec_helper"
require "omnizip/algorithms/bzip2/bwt"

RSpec.describe Omnizip::Algorithms::BZip2::Bwt do
  describe ".encode / .decode round-trip" do
    it "round-trips small inputs of varying lengths" do
      rng = Random.new(42)
      (0..20).each do |i|
        data = rng.bytes(5 + (i * 13))
        t, idx = described_class.new.encode(data)
        expect(described_class.new.decode(t, idx)).to eq(data)
      end
    end

    it "round-trips repetitive inputs" do
      ["", "a", "aaaa", "ab" * 50, "hello world hello world"].each do |d|
        t, idx = described_class.new.encode(d)
        expect(described_class.new.decode(t, idx)).to eq(d)
      end
    end
  end
end
