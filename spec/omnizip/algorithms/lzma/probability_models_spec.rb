# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::ProbabilityModels do
  describe "#initialize" do
    it "initializes with default lc/lp/pb" do
      models = described_class.new
      expect(models.literal).to be_an(Array)
      expect(models.is_match).to be_an(Array)
    end

    it "correctly sizes literal models based on lc+lp" do
      models = described_class.new(lc: 3, lp: 0)
      # (1 << (3+0)) * 0x300 = 8 * 768 = 6144
      expect(models.literal.size).to eq(6144)
    end
  end

  describe "is_match models" do
    it "has STATES * POS_STATES_MAX models" do
      models = described_class.new(pb: 2)
      # 12 states * 4 pos_states = 48
      expect(models.is_match.size).to eq(48)
    end
  end
end
