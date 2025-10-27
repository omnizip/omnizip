# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::AlgorithmRegistry do
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe ".register" do
    it "registers an algorithm class" do
      algorithm_class = Class.new
      described_class.register(:test, algorithm_class)

      expect(described_class.get(:test)).to eq(algorithm_class)
    end

    it "raises error when name is nil" do
      expect do
        described_class.register(nil, Class.new)
      end.to raise_error(ArgumentError, /name cannot be nil/)
    end

    it "raises error when class is nil" do
      expect do
        described_class.register(:test, nil)
      end.to raise_error(ArgumentError, /class cannot be nil/)
    end
  end

  describe ".get" do
    it "retrieves registered algorithm" do
      algorithm_class = Class.new
      described_class.register(:test, algorithm_class)

      expect(described_class.get(:test)).to eq(algorithm_class)
    end

    it "raises UnknownAlgorithmError for unregistered algorithm" do
      expect do
        described_class.get(:nonexistent)
      end.to raise_error(Omnizip::UnknownAlgorithmError, /Unknown algorithm/)
    end
  end

  describe ".registered?" do
    it "returns true for registered algorithm" do
      described_class.register(:test, Class.new)

      expect(described_class.registered?(:test)).to be true
    end

    it "returns false for unregistered algorithm" do
      expect(described_class.registered?(:nonexistent)).to be false
    end
  end

  describe ".available" do
    it "returns list of registered algorithm names" do
      described_class.register(:algo1, Class.new)
      described_class.register(:algo2, Class.new)

      available = described_class.available

      expect(available).to contain_exactly(:algo1, :algo2)
    end

    it "returns empty array when no algorithms registered" do
      expect(described_class.available).to eq([])
    end
  end
end
