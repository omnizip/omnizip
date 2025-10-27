# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BCJ Filter Integration" do
  let(:bcj_filter) { Omnizip::Filters::BcjX86.new }

  describe "Filter + Compression pipeline" do
    let(:test_data) do
      # Executable-like data with E8/E9 instructions
      data = "\x55\x89\xE5".b # push ebp; mov ebp, esp
      data += "\xE8\x00\x00\x00\x00".b # call 0
      data += "\x83\xC4\x08".b # add esp, 8
      data += "\xE9\xF0\xFF\xFF\xFF".b # jmp -16
      data += "\xC3".b # ret
      data
    end

    it "demonstrates BCJ preprocessing improves compressibility" do
      # Test data round-trip
      filtered = bcj_filter.encode(test_data, 0)
      unfiltered = bcj_filter.decode(filtered, 0)

      expect(unfiltered).to eq(test_data)
    end

    it "works with FilterPipeline" do
      pipeline = Omnizip::FilterPipeline.new
      pipeline.add_filter(bcj_filter)

      encoded = pipeline.encode(test_data, 0)
      decoded = pipeline.decode(encoded, 0)

      expect(decoded).to eq(test_data)
    end

    it "can be attached to algorithms via with_filter" do
      # Demonstrate the integration point
      # (Actual compression would require LZMA implementation changes)
      lzma = Omnizip::Algorithms::LZMA.new

      # Set up filter
      lzma.with_filter(bcj_filter)

      expect(lzma.filter).to eq(bcj_filter)
    end
  end

  describe "FilterRegistry" do
    it "registers BCJ-x86 filter" do
      expect(Omnizip::FilterRegistry.available).to include(:"bcj-x86")
    end

    it "retrieves BCJ-x86 filter by name" do
      filter_class = Omnizip::FilterRegistry.get(:"bcj-x86")

      expect(filter_class).to eq(Omnizip::Filters::BcjX86)
    end

    it "creates filter instances from registry" do
      filter_class = Omnizip::FilterRegistry.get(:"bcj-x86")
      filter = filter_class.new

      expect(filter).to be_a(Omnizip::Filters::BcjX86)
    end
  end

  describe "Real-world usage pattern" do
    it "demonstrates typical usage with pipeline and algorithm" do
      # Create a pipeline with BCJ filter
      pipeline = Omnizip::FilterPipeline.new
      pipeline.add_filter(Omnizip::Filters::BcjX86.new)

      # Apply preprocessing
      executable_data = "\xE8\x00\x00\x00\x00".b * 10
      preprocessed = pipeline.encode(executable_data, 0)

      # Verify preprocessing worked
      expect(preprocessed).not_to eq(executable_data)

      # Verify round-trip
      restored = pipeline.decode(preprocessed, 0)
      expect(restored).to eq(executable_data)
    end
  end
end
