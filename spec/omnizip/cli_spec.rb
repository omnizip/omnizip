# frozen_string_literal: true

require "spec_helper"
require "omnizip/cli"
require "fileutils"
require "tmpdir"

RSpec.describe Omnizip::Cli do
  it "boots (the executable calls Omnizip::Cli.start)" do
    expect(described_class).to be < Thor
    expect(described_class).to respond_to(:start)
  end

  it "round-trips the documented compress/decompress commands" do
    Dir.mktmpdir("omnizip-cli") do |dir|
      input = File.join(dir, "input.txt")
      File.binwrite(input, "documented CLI round-trip\n" * 500)

      compressed = File.join(dir, "output.lzma")
      described_class.start(["compress", input, compressed, "--level", "9"])
      expect(File.binread(compressed, 2)).not_to eq("PK")

      restored = File.join(dir, "restored.txt")
      described_class.start(["decompress", compressed, restored])
      expect(File.binread(restored)).to eq(File.binread(input))
    end
  end

  it "writes a real LZMA_Alone container from the CLI" do
    Dir.mktmpdir("omnizip-cli") do |dir|
      input = File.join(dir, "input.txt")
      File.binwrite(input, "lzma container check\n" * 300)

      compressed = File.join(dir, "output.lzma")
      described_class.start(["compress", input, compressed])

      header = File.binread(compressed, 13)
      expect(header.getbyte(0)).to eq((((2 * 5) + 0) * 9) + 3)
    end
  end

  describe "help flags on subcommands" do
    {
      ["--help"] => "Commands",
      ["help"] => "Commands",
      ["compress", "--help"] => "compress INPUT OUTPUT",
      ["version", "-h"] => "Usage",
      ["archive", "--help"] => "archive create",
      ["archive", "create", "--help"] => "archive create OUTPUT INPUT",
      ["archive", "extract", "-h"] => "archive extract",
      ["profile", "show", "--help"] => "profile show PROFILE",
      ["convert", "-h"] => "Usage",
    }.each do |args, expected|
      it "prints help for: omnizip #{args.join(' ')}" do
        expect do
          described_class.start(args)
        end.to output(/#{Regexp.escape(expected)}/).to_stdout
      end
    end
  end
end
