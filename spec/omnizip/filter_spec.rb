# frozen_string_literal: true

require "spec_helper"
require "omnizip/filter"

RSpec.describe Omnizip::Filter do
  let(:filter_class) do
    Class.new(Omnizip::Filter) do
      def initialize(architecture:, name: "Test")
        super
      end

      def id_for_format(format)
        format == :test ? 0x01 : 0x02
      end

      def encode(data, _position = 0)
        data
      end

      def decode(data, _position = 0)
        data
      end

      def self.metadata
        { name: "Test", description: "Test filter" }
      end
    end
  end

  describe "#initialize" do
    it "stores architecture" do
      filter = filter_class.new(architecture: :x86)
      expect(filter.architecture).to eq(:x86)
    end

    it "stores name" do
      filter = filter_class.new(architecture: :x86, name: "Test")
      expect(filter.name).to eq("Test")
    end
  end

  describe "#id_for_format" do
    it "returns format-specific ID" do
      filter = filter_class.new(architecture: :x86)
      expect(filter.id_for_format(:test)).to eq(0x01)
      expect(filter.id_for_format(:other)).to eq(0x02)
    end
  end

  describe "#encode" do
    it "returns encoded data" do
      filter = filter_class.new(architecture: :x86)
      data = "test"
      expect(filter.encode(data)).to eq(data)
    end

    it "passes position parameter" do
      filter = filter_class.new(architecture: :x86)
      data = "test"
      expect(filter.encode(data, 100)).to eq(data)
    end
  end

  describe "#decode" do
    it "returns decoded data" do
      filter = filter_class.new(architecture: :x86)
      data = "test"
      expect(filter.decode(data)).to eq(data)
    end

    it "passes position parameter" do
      filter = filter_class.new(architecture: :x86)
      data = "test"
      expect(filter.decode(data, 100)).to eq(data)
    end
  end

  describe ".metadata" do
    it "returns filter metadata" do
      expect(filter_class.metadata).to eq({ name: "Test",
                                            description: "Test filter" })
    end
  end

  describe "interface contract" do
    it "raises NotImplementedError for unimplemented id_for_format" do
      # Create a minimal class without id_for_format implementation
      minimal_class = Class.new(Omnizip::Filter) do
        def initialize(architecture:, name: "Minimal")
          super
        end
        # encode, decode, and metadata not implemented
      end

      filter = minimal_class.new(architecture: :x86)
      expect do
        filter.id_for_format(:xz)
      end.to raise_error(NotImplementedError,
                         /must implement/)
    end

    it "raises NotImplementedError for unimplemented encode" do
      minimal_class = Class.new(Omnizip::Filter) do
        def initialize(architecture:, name: "Minimal")
          super
        end
        # decode and other methods not implemented
      end

      filter = minimal_class.new(architecture: :x86)
      expect do
        filter.encode("test")
      end.to raise_error(NotImplementedError, /must implement/)
    end

    it "raises NotImplementedError for unimplemented decode" do
      minimal_class = Class.new(Omnizip::Filter) do
        def initialize(architecture:, name: "Minimal")
          super
        end
        # encode and other methods not implemented
      end

      filter = minimal_class.new(architecture: :x86)
      expect do
        filter.decode("test")
      end.to raise_error(NotImplementedError, /must implement/)
    end

    it "raises NotImplementedError for unimplemented metadata" do
      # Use the base class directly
      expect do
        Omnizip::Filter.metadata
      end.to raise_error(NotImplementedError,
                         /must implement/)
    end
  end
end
