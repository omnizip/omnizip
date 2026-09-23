# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/writer"
require "omnizip/formats/rar/reader"
require "fileutils"

ORACLE = File.expand_path("../../../fixtures/rar/oracle", __dir__).freeze
FROZEN_ARCHIVE = File.join(ORACLE, "rar4_store_tree.rar").freeze
FROZEN_LISTING = File.join(ORACLE, "rar4_store_tree.unrar-l.txt").freeze

RSpec.describe "RAR4 STORE interoperability (oracle-frozen fixtures)",
               :integration do
  # The archive these examples build was validated once by the unrar CLI
  # (test + extract) and frozen into spec/fixtures/rar/oracle by
  # scripts/generate_rar_oracle_fixtures.rb — CI needs no oracle.
  let(:temp_dir) { Dir.mktmpdir("omnizip_rar4_interop") }
  let(:archive) { File.join(temp_dir, "interop.rar") }
  let(:big_file) { File.join(temp_dir, "big.txt") }
  let(:tree_root) { File.join(temp_dir, "tree") }

  before do
    skip "oracle fixtures missing" unless File.exist?(FROZEN_ARCHIVE)

    File.binwrite(big_file, "omnizip RAR4 interop fixture. " * 800)
    FileUtils.mkdir_p(File.join(tree_root, "sub"))
    File.binwrite(File.join(tree_root, "README.md"), "# tree\n")
    File.binwrite(File.join(tree_root, "sub", "main.rb"), "puts 'hi'\n")
    File.binwrite(File.join(tree_root, "empty.bin"), "")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def build_archive
    writer = Omnizip::Formats::Rar::Writer.new(archive, compression: :store)
    writer.add_file(big_file)
    writer.add_directory(tree_root)
    writer.write
  end

  # No byte-compare against the fixture here: the RAR4 writer embeds DOS
  # local-time timestamps, so fresh bytes differ across timezones/machines.
  # The frozen archive still pins the decode path: it is the exact byte
  # sequence the official unrar once accepted, and omnizip must decode it
  # to the original content forever.
  def decode_archive(path, out)
    reader = Omnizip::Formats::Rar::Reader.new(path)
    reader.open
    FileUtils.mkdir_p(out)

    reader.list_files.each do |entry|
      next if entry.directory?

      target = File.join(out, entry.name)
      FileUtils.mkdir_p(File.dirname(target))
      reader.extract_entry(entry.name, target)
    end
  end

  it "decodes the frozen unrar-validated archive to the original content" do
    out = File.join(temp_dir, "out_frozen")
    decode_archive(FROZEN_ARCHIVE, out)

    expect(FileUtils.compare_file(big_file, File.join(out, "big.txt"))).to be(true)
    expect(FileUtils.compare_file(File.join(tree_root, "README.md"),
                                  File.join(out, "README.md"))).to be(true)
    expect(FileUtils.compare_file(File.join(tree_root, "sub", "main.rb"),
                                  File.join(out, "sub", "main.rb"))).to be(true)
    expect(File.size(File.join(out, "empty.bin"))).to eq(0)
  end

  it "a fresh archive decodes identically to the frozen one" do
    build_archive

    out_fresh = File.join(temp_dir, "out_fresh")
    out_frozen = File.join(temp_dir, "out_frozen")
    decode_archive(archive, out_fresh)
    decode_archive(FROZEN_ARCHIVE, out_frozen)

    big = File.binread(big_file)
    expect(File.binread(File.join(out_fresh, "big.txt"))).to eq(big)
    expect(File.binread(File.join(out_frozen, "big.txt"))).to eq(big)
    expect(File.binread(File.join(out_fresh, "sub/main.rb"))).to eq("puts 'hi'\n")
    expect(File.binread(File.join(out_frozen, "sub/main.rb"))).to eq("puts 'hi'\n")
  end

  it "the frozen oracle listing records the archive contents" do
    listing = File.read(FROZEN_LISTING)

    expect(listing).to include("big.txt", "README.md", "main.rb", "empty.bin")
    expect(listing).not_to match(/corrupt|ERROR/i)
  end
end
