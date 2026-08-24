# frozen_string_literal: true

require "spec_helper"
require "etc"

RSpec.describe Omnizip::Models::ParallelOptions do
  describe "defaults" do
    it "detects the CPU count for threads" do
      expect(described_class.new.threads).to eq(Etc.nprocessors)
    end

    it "uses the documented static defaults" do
      options = described_class.new

      expect(options.queue_size).to eq(1000)
      expect(options.chunk_size).to eq(67_108_864)
      expect(options.strategy).to eq(:dynamic)
      expect(options.verbose).to be false
      expect(options.batch_size).to eq(10)
    end
  end

  describe "#to_hash" do
    it "emits every key even when nothing was assigned" do
      expect(described_class.new.to_hash).to eq(
        "threads" => Etc.nprocessors,
        "queue_size" => 1000,
        "chunk_size" => 67_108_864,
        "strategy" => :dynamic,
        "verbose" => false,
        "batch_size" => 10,
      )
    end

    it "keeps every key when values are explicitly nil" do
      options = described_class.new(
        threads: nil,
        queue_size: nil,
        chunk_size: nil,
        strategy: nil,
        verbose: nil,
        batch_size: nil,
      )

      expect(options.to_hash).to eq(
        "threads" => nil,
        "queue_size" => nil,
        "chunk_size" => nil,
        "strategy" => nil,
        "verbose" => nil,
        "batch_size" => nil,
      )
    end
  end

  describe "#apply" do
    it "sets known keys and ignores unknown ones" do
      options = described_class.new.apply(threads: 3, bogus: 9)

      expect(options.threads).to eq(3)
      expect(options.to_hash).to eq(
        "threads" => 3,
        "queue_size" => 1000,
        "chunk_size" => 67_108_864,
        "strategy" => :dynamic,
        "verbose" => false,
        "batch_size" => 10,
      )
    end

    it "returns self so it can be chained" do
      options = described_class.new

      expect(options.apply(batch_size: 7)).to equal(options)
    end

    it "recognizes Symbol keys only, so to_hash output is not accepted" do
      options = described_class.new.apply("threads" => 3)

      expect(options.threads).to eq(Etc.nprocessors)
    end
  end

  describe "#dup" do
    it "does not leak mutations back into the original" do
      original = described_class.new
      copy = original.dup
      copy.threads = 99

      expect(copy.threads).to eq(99)
      expect(original.threads).to eq(Etc.nprocessors)
      expect(original.to_hash["threads"]).to eq(Etc.nprocessors)
    end

    it "does not leak an explicit nil back into the original" do
      original = described_class.new
      copy = original.dup
      copy.threads = nil

      expect(original.to_hash["threads"]).to eq(Etc.nprocessors)
      expect(copy.to_hash).to include("threads" => nil)
    end
  end

  describe "#validate!" do
    it "keeps the inherited lutaml validate! callable on a valid instance" do
      options = described_class.new

      expect { options.validate! }.not_to raise_error
    end
  end

  describe "#validate_options!" do
    it "rejects a non-positive thread count" do
      options = described_class.new
      options.threads = 0

      expect { options.validate_options! }
        .to raise_error(ArgumentError, "threads must be > 0")
    end

    it "rejects an unknown strategy" do
      options = described_class.new
      options.strategy = :bogus

      expect { options.validate_options! }
        .to raise_error(ArgumentError, "strategy must be :dynamic or :static")
    end

    # An explicit nil used to reach `nil <= 0` and raise NoMethodError.
    %i[threads queue_size chunk_size batch_size].each do |field|
      it "rejects a nil #{field} with ArgumentError, not NoMethodError" do
        options = described_class.new
        options.public_send("#{field}=", nil)

        expect { options.validate_options! }
          .to raise_error(ArgumentError, "#{field} must be > 0")
      end
    end
  end
end
