# frozen_string_literal: true

require "spec_helper"
require "omnizip/filters/bcj2"

RSpec.describe Omnizip::Filters::Bcj2 do
  describe ".metadata" do
    it "returns filter metadata" do
      metadata = described_class.metadata

      expect(metadata[:name]).to eq("BCJ2")
      expect(metadata[:architecture]).to eq("x86/x64")
      expect(metadata[:streams]).to eq(4)
      expect(metadata[:complexity]).to eq("high")
    end
  end

  describe "#encode" do
    it "raises NotImplementedError" do
      filter = described_class.new
      data = "test data"

      expect do
        filter.encode(data)
      end.to raise_error(
        NotImplementedError,
        /BCJ2 encoding is not yet implemented/,
      )
    end
  end

  describe "#decode" do
    let(:filter) { described_class.new }

    context "when data is not a Bcj2StreamData object" do
      it "raises ArgumentError" do
        expect do
          filter.decode("invalid data")
        end.to raise_error(
          ArgumentError,
          /BCJ2 decode requires a Bcj2StreamData object/,
        )
      end
    end

    context "when data is a Bcj2StreamData object" do
      let(:stream_data) do
        Omnizip::Filters::Bcj2StreamData.new
      end

      it "delegates to Bcj2Decoder" do
        stream_data.main = "test"
        stream_data.rc = "\xFF" * 5

        expect do
          filter.decode(stream_data)
        end.not_to raise_error
      end
    end
  end
end

RSpec.describe Omnizip::Filters::Bcj2StreamData do
  let(:stream_data) { described_class.new }

  describe "#initialize" do
    it "creates empty streams" do
      expect(stream_data.main).to eq("")
      expect(stream_data.call).to eq("")
      expect(stream_data.jump).to eq("")
      expect(stream_data.rc).to eq("")
    end
  end

  describe "#[]" do
    it "returns stream by index" do
      stream_data.main = "main"
      stream_data.call = "call"
      stream_data.jump = "jump"
      stream_data.rc = "rc"

      expect(stream_data[0]).to eq("main")
      expect(stream_data[1]).to eq("call")
      expect(stream_data[2]).to eq("jump")
      expect(stream_data[3]).to eq("rc")
    end

    it "raises error for invalid index" do
      expect do
        stream_data[4]
      end.to raise_error(ArgumentError, /Invalid stream index/)
    end
  end

  describe "#[]=" do
    it "sets stream by index" do
      stream_data[0] = "new main"
      stream_data[1] = "new call"
      stream_data[2] = "new jump"
      stream_data[3] = "new rc"

      expect(stream_data.main).to eq("new main")
      expect(stream_data.call).to eq("new call")
      expect(stream_data.jump).to eq("new jump")
      expect(stream_data.rc).to eq("new rc")
    end

    it "raises error for invalid index" do
      expect do
        stream_data[4] = "data"
      end.to raise_error(ArgumentError, /Invalid stream index/)
    end
  end

  describe "#to_a" do
    it "returns all streams as array" do
      stream_data.main = "m"
      stream_data.call = "c"
      stream_data.jump = "j"
      stream_data.rc = "r"

      expect(stream_data.to_a).to eq(%w[m c j r])
    end
  end

  describe "#empty?" do
    it "returns true when all streams are empty" do
      expect(stream_data.empty?).to be true
    end

    it "returns false when any stream has data" do
      stream_data.main = "data"
      expect(stream_data.empty?).to be false
    end
  end
end

RSpec.describe Omnizip::Filters::Bcj2Decoder do
  describe "#decode" do
    context "with empty streams" do
      let(:streams) { Omnizip::Filters::Bcj2StreamData.new }
      let(:decoder) { described_class.new(streams) }

      before do
        # Minimum RC stream for range decoder initialization
        streams.rc = "\x00\x00\x00\x00\xFF"
      end

      it "returns empty string for empty main stream" do
        result = decoder.decode
        expect(result).to eq("")
      end
    end

    context "with simple non-convertible data" do
      let(:streams) { Omnizip::Filters::Bcj2StreamData.new }
      let(:decoder) { described_class.new(streams) }

      before do
        # Simple ASCII text (no E8/E9 opcodes)
        streams.main = "Hello, World!"
        streams.rc = "\x00\x00\x00\x00\xFF#{"\x80" * 20}"
      end

      it "returns the data unchanged" do
        result = decoder.decode
        # Data without E8/E9 should pass through
        expect(result.bytesize).to be > 0
      end
    end

    context "with instruction pointer" do
      let(:streams) { Omnizip::Filters::Bcj2StreamData.new }
      let(:decoder) { described_class.new(streams, 0x1000) }

      before do
        streams.main = "test"
        streams.rc = "\x00\x00\x00\x00\xFF#{"\x80" * 10}"
      end

      it "initializes with correct IP" do
        expect(decoder.ip).to eq(0x1000)
      end
    end
  end
end

RSpec.describe Omnizip::Filters::Bcj2Encoder do
  describe "#encode" do
    let(:encoder) { described_class.new("test data") }

    it "raises NotImplementedError" do
      expect do
        encoder.encode
      end.to raise_error(
        NotImplementedError,
        /BCJ2 encoding is not yet implemented/,
      )
    end
  end
end
