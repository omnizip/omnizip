# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Convenience with tar format" do
  let(:work_dir) { Dir.mktmpdir("omnizip-tar-convenience") }

  after { FileUtils.rm_rf(work_dir) }

  it "round-trips paths longer than the ustar name field via prefix split" do
    src = File.join(work_dir, "payload.bin")
    File.binwrite(src, "payload")
    long_name = "#{'d' * 60}/x#{'d' * 60}/final.txt"
    archive = File.join(work_dir, "long.tar")

    Omnizip::Archive.create(archive, format: :tar) do |b|
      b.add_file(src, long_name)
    end

    entries = Omnizip::Formats::Tar::Reader.new(archive)
      .read.entries.map(&:name)
    expect(entries).to include(long_name)

    if system("tar --version > /dev/null 2>&1")
      expect(`tar -tf #{archive}`.strip).to include(long_name)
    end
  end

  it "raises truthfully for paths no ustar fields can represent" do
    src = File.join(work_dir, "payload.bin")
    File.binwrite(src, "payload")

    expect do
      Omnizip::Archive.create(File.join(work_dir, "bad.tar"),
                              format: :tar) do |b|
        b.add_file(src, "z" * 120)
      end
    end.to raise_error(Omnizip::FormatError, /too long/)
  end

  it "compresses and lists via format: :tar" do
    src = File.join(work_dir, "hello.txt")
    File.write(src, "tar contents")
    archive = File.join(work_dir, "out.tar")

    Omnizip.compress_file(src, archive, format: :tar)

    entries = Omnizip.list_archive(archive, format: :tar)
    expect(entries).to include("hello.txt")
  end

  it "reads back an entry via format: :tar" do
    src = File.join(work_dir, "data.txt")
    File.write(src, "payload")
    archive = File.join(work_dir, "data.tar")

    Omnizip.compress_file(src, archive, format: :tar)
    contents = Omnizip.read_from_archive(archive, "data.txt", format: :tar)
    expect(contents).to eq("payload")
  end

  it "raises UnsupportedFormatError for unknown formats" do
    src = File.join(work_dir, "any.txt")
    File.write(src, "x")
    expect do
      Omnizip.compress_file(src, "any.out", format: :nope)
    end.to raise_error(Omnizip::UnsupportedFormatError)
  end
end
