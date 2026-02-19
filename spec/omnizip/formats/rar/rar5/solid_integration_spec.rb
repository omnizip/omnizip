# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/writer"
require "tempfile"
require "tmpdir"

RSpec.describe "RAR5 Solid Compression Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:archive_path) { File.join(temp_dir, "test_solid.rar") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "solid archive creation" do
    it "creates solid archive with multiple files" do
      # Create test files
      file1 = File.join(temp_dir, "test1.txt")
      file2 = File.join(temp_dir, "test2.txt")
      file3 = File.join(temp_dir, "test3.txt")

      File.write(file1, "This is test file 1")
      File.write(file2, "This is test file 2")
      File.write(file3, "This is test file 3")

      # Create solid archive
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       level: 3,
                                                       solid: true)

      writer.add_file(file1)
      writer.add_file(file2)
      writer.add_file(file3)

      result = writer.write

      expect(result).to eq(archive_path)
      expect(File.exist?(archive_path)).to be true
      expect(File.size(archive_path)).to be > 0
    end

    it "achieves better compression with solid mode" do
      # Create files with similar content
      files = []
      5.times do |i|
        path = File.join(temp_dir, "similar#{i}.txt")
        # Repetitive content compresses well in solid mode
        File.write(path, "def hello_#{i}\n  puts 'Hello World'\nend\n" * 10)
        files << path
      end

      # Create non-solid archive
      non_solid_path = File.join(temp_dir, "non_solid.rar")
      writer_non_solid = Omnizip::Formats::Rar::Rar5::Writer.new(non_solid_path,
                                                                 compression: :lzma,
                                                                 level: 3,
                                                                 solid: false)
      files.each { |f| writer_non_solid.add_file(f) }
      writer_non_solid.write

      # Create solid archive
      solid_path = File.join(temp_dir, "solid.rar")
      writer_solid = Omnizip::Formats::Rar::Rar5::Writer.new(solid_path,
                                                             compression: :lzma,
                                                             level: 3,
                                                             solid: true)
      files.each { |f| writer_solid.add_file(f) }
      writer_solid.write

      non_solid_size = File.size(non_solid_path)
      solid_size = File.size(solid_path)

      # Solid should be smaller due to shared dictionary
      expect(solid_size).to be < non_solid_size

      # Calculate improvement (should be at least 10%)
      improvement = ((non_solid_size - solid_size).to_f / non_solid_size) * 100
      expect(improvement).to be >= 10.0
    end
  end

  describe "solid archive with directory" do
    it "compresses directory in solid mode" do
      # Create directory structure
      source_dir = File.join(temp_dir, "source")
      FileUtils.mkdir_p(File.join(source_dir, "subdir"))

      File.write(File.join(source_dir, "file1.rb"), "class Test1; end")
      File.write(File.join(source_dir, "file2.rb"), "class Test2; end")
      File.write(File.join(source_dir, "subdir", "file3.rb"),
                 "class Test3; end")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       level: 5,
                                                       solid: true)

      writer.add_directory(source_dir)
      writer.write

      expect(File.exist?(archive_path)).to be true
      expect(File.size(archive_path)).to be > 0
    end
  end

  describe "solid compression levels" do
    let(:test_content) { "Lorem ipsum dolor sit amet. " * 50 }

    it "higher levels produce smaller archives" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, test_content)

      sizes = {}
      [1, 3, 5].each do |level|
        path = File.join(temp_dir, "solid_level#{level}.rar")
        writer = Omnizip::Formats::Rar::Rar5::Writer.new(path,
                                                         compression: :lzma,
                                                         level: level,
                                                         solid: true)
        writer.add_file(test_file)
        writer.write

        sizes[level] = File.size(path)
      end

      # Level 5 should be same or smaller than level 1
      expect(sizes[5]).to be <= sizes[1]
    end
  end

  describe "RAR5 signature and format" do
    it "writes correct RAR5 signature" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test content")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       solid: true)
      writer.add_file(test_file)
      writer.write

      # Read RAR5 signature (first 8 bytes)
      signature = File.binread(archive_path, 8)
      expected = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*")

      expect(signature).to eq(expected)
    end
  end

  describe "error handling" do
    it "raises error for non-existent file" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       solid: true)

      expect do
        writer.add_file("/nonexistent/file.txt")
      end.to raise_error(ArgumentError, /File not found/)
    end

    it "raises error for non-existent directory" do
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       solid: true)

      expect do
        writer.add_directory("/nonexistent/directory")
      end.to raise_error(ArgumentError, /Directory not found/)
    end
  end
end
