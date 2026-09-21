# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "omnizip/implementations/rust"

# Archive-level tier: whole-archive open/list/read over the cdylib,
# differential against the pure-Ruby zip reader.
RSpec.describe Omnizip::Implementations::Rust::Archive do
  let(:library) { Omnizip::Implementations::Rust::Library }

  def zip_bytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.zip")
      Omnizip::Zip::File.open(path, create: true) do |zip|
        zip.send(:add_data, "a.bin", (0..30_000).map { |i| (i % 251).chr }.join)
        zip.send(:add_data, "b.txt", "hello archive tier")
      end
      File.binread(path)
    end
  end

  def ruby_reader_names(bytes)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.zip")
      File.binwrite(path, bytes)
      Omnizip::Formats::Zip::Reader.new(path).entries.map(&:filename)
    end
  end

  it "lists and reads entries identically to the Ruby reader" do
    skip "omnizip-ffi cdylib not built" if library.instance.nil?

    bytes = zip_bytes
    described_class.open(bytes) do |arch|
      expect(arch.entry_count).to eq(2)
      names = arch.entry_names
      expect(names.sort).to eq(ruby_reader_names(bytes).sort)
      expect(arch.read_entry(names.index("b.txt"))).to eq("hello archive tier")
      expect(arch.read_entry(names.index("a.bin")).bytesize).to eq(30_001)
    end
  end

  it "agrees with the Ruby reader on the same bytes (fallback parity)" do
    bytes = zip_bytes
    expect(ruby_reader_names(bytes)).to include("a.bin", "b.txt")
  end
end
