# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

RSpec.describe Omnizip::IO::Source do
  describe ".for" do
    it "wraps a StringIO without copying" do
      io = StringIO.new("hello")
      source = described_class.for(io)
      expect(source.read).to eq("hello")
    end

    it "reads a file when given an existing path" do
      file = Tempfile.create("source-spec")
      file.write("on disk")
      file.close
      path = file.path
      begin
        expect(described_class.for(path).read).to eq("on disk")
      ensure
        File.delete(path)
      end
    end

    it "treats a non-path string as literal data" do
      expect(described_class.for("raw bytes").read).to eq("raw bytes")
    end

    it "resolves ::Tempfile even when tempfile was not yet required (issue #26)" do
      # The `when ::Tempfile` clause triggers a NameError in a clean process
      # unless io/source requires the tempfile stdlib itself.
      lib = File.expand_path("../../../../lib", __dir__)
      code = 'require "omnizip"; print Omnizip::IO::Source.for("abc").read'
      out = IO.popen(
        [RbConfig.ruby, "-I", lib, "-e", code],
        err: %i[child out], &:read
      )
      expect($?).to be_success
      expect(out).to eq("abc")
    end

    it "raises ArgumentError for unsupported types" do
      expect { described_class.for(42) }.to raise_error(ArgumentError)
    end
  end

  describe "#close" do
    it "closes the wrapped IO when supported" do
      io = StringIO.new("data")
      described_class.for(io).close
      expect(io.closed?).to be true
    end
  end
end

RSpec.describe Omnizip::IO::Sink do
  describe ".for" do
    it "writes to a StringIO" do
      io = StringIO.new
      described_class.for(io).write("payload")
      expect(io.string).to eq("payload")
    end

    it "writes to a file when given a path" do
      file = Tempfile.create("sink-spec")
      file.close
      path = file.path
      begin
        described_class.for(path).write("on disk")
        expect(File.binread(path)).to eq("on disk")
      ensure
        FileUtils.rm_f(path)
      end
    end

    it "raises ArgumentError for unsupported types" do
      expect { described_class.for(42) }.to raise_error(ArgumentError)
    end
  end
end
