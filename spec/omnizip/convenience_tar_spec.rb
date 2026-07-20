# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Convenience with tar format" do
  let(:work_dir) { Dir.mktmpdir("omnizip-tar-convenience") }

  after { FileUtils.rm_rf(work_dir) }

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
