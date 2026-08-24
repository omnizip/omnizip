# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::ETAResult do
  describe "#to_hash" do
    it "omits attributes that were never assigned" do
      result = described_class.new
      result.seconds_remaining = 150.0
      result.formatted = "2m 30s"

      expect(result.to_hash).to eq(
        "seconds_remaining" => 150.0,
        "formatted" => "2m 30s",
      )
    end

    it "emits every assigned attribute" do
      result = described_class.new
      result.seconds_remaining = 150.0
      result.formatted = "2m 30s"
      result.confidence_lower = 120.0
      result.confidence_upper = 180.0

      expect(result.to_hash).to eq(
        "seconds_remaining" => 150.0,
        "formatted" => "2m 30s",
        "confidence_lower" => 120.0,
        "confidence_upper" => 180.0,
      )
    end
  end

  describe "#reliable?" do
    it "is true when the confidence interval is within 50% of the estimate" do
      result = described_class.new
      result.seconds_remaining = 150.0
      result.confidence_lower = 120.0
      result.confidence_upper = 180.0

      expect(result.reliable?).to be true
    end

    it "is false when the confidence interval is too wide" do
      result = described_class.new
      result.seconds_remaining = 100.0
      result.confidence_lower = 10.0
      result.confidence_upper = 200.0

      expect(result.reliable?).to be false
    end

    it "is false when the confidence bounds were never set" do
      result = described_class.new
      result.seconds_remaining = 100.0

      expect(result.reliable?).to be false
    end
  end
end
