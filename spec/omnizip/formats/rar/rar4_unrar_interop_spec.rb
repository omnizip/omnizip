# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/writer"
require "omnizip/formats/rar/reader"
require "fileutils"

RSpec.describe "RAR4 unrar interoperability",
               :integration,
               skip: !system("which unrar > /dev/null 2>&1") do
  let(:temp_dir) { Dir.mktmpdir("omnizip_rar4_interop") }
  let(:archive) { File.join(temp_dir, "interop.rar") }
  let(:big_file) { File.join(temp_dir, "big.txt") }
  let(:tree_root) { File.join(temp_dir, "tree") }

  before do
    File.binwrite(big_file, "omnizip RAR4 interop fixture. " * 800)
    FileUtils.mkdir_p(File.join(tree_root, "sub"))
    File.binwrite(File.join(tree_root, "README.md"), "# tree\n")
    File.binwrite(File.join(tree_root, "sub", "main.rb"), "puts 'hi'\n")
    File.binwrite(File.join(tree_root, "empty.bin"), "")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def run_unrar(*args)
    system("unrar", *args, out: File::NULL, err: File::NULL)
  end

  def build_archive
    writer = Omnizip::Formats::Rar::Writer.new(archive, compression: :store)
    writer.add_file(big_file)
    writer.add_directory(tree_root)
    writer.write
  end

  it "creates STORE archives that unrar tests clean" do
    build_archive

    expect(run_unrar("t", archive)).to be true
  end

  it "extracts STORE archives to byte-identical files and directories" do
    build_archive

    out = File.join(temp_dir, "out")
    FileUtils.mkdir_p(out)
    expect(run_unrar("x", "-o+", archive, "#{out}/")).to be true

    expect(FileUtils.compare_file(big_file, File.join(out, "big.txt"))).to be(true)
    expect(File.directory?(File.join(out, "sub"))).to be(true)
    expect(FileUtils.compare_file(File.join(tree_root, "sub", "main.rb"),
                                  File.join(out, "sub", "main.rb"))).to be(true)
    expect(FileUtils.compare_file(File.join(tree_root, "README.md"),
                                  File.join(out, "README.md"))).to be(true)
    expect(File.size(File.join(out, "empty.bin"))).to eq(0)
  end

  it "omnizip reads back its own STORE archive identically" do
    build_archive

    reader = Omnizip::Formats::Rar::Reader.new(archive)
    reader.open
    names = reader.list_files.map(&:name)

    expect(names).to include("big.txt", "README.md", "sub", "sub/main.rb",
                             "empty.bin")
    expect(reader.list_files.find { |e| e.name == "sub" }).to be_directory
  end
end
