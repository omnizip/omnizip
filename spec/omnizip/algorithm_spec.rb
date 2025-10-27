# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithm do
  let(:test_algorithm_class) do
    Class.new(described_class) do
      def self.metadata
        Omnizip::Models::AlgorithmMetadata.new(
          name: "test",
          description: "Test algorithm",
          version: "1.0"
        )
      end
    end
  end

  describe "#initialize" do
    it "accepts options hash" do
      algorithm = test_algorithm_class.new(level: 5)

      expect(algorithm.options).to eq(level: 5)
    end

    it "defaults to empty options hash" do
      algorithm = test_algorithm_class.new

      expect(algorithm.options).to eq({})
    end
  end

  describe "#compress" do
    it "raises NotImplementedError" do
      algorithm = test_algorithm_class.new

      expect do
        algorithm.compress(StringIO.new, StringIO.new)
      end.to raise_error(NotImplementedError, /must implement #compress/)
    end
  end

  describe "#decompress" do
    it "raises NotImplementedError" do
      algorithm = test_algorithm_class.new

      expect do
        algorithm.decompress(StringIO.new, StringIO.new)
      end.to raise_error(NotImplementedError, /must implement #decompress/)
    end
  end

  describe ".metadata" do
    it "raises NotImplementedError for base class" do
      expect do
        described_class.metadata
      end.to raise_error(NotImplementedError, /must implement .metadata/)
    end

    it "returns metadata for subclass" do
      metadata = test_algorithm_class.metadata

      expect(metadata).to be_a(Omnizip::Models::AlgorithmMetadata)
      expect(metadata.name).to eq("test")
    end
  end
end
