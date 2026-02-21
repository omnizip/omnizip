# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "fileutils"
require "tempfile"

module Omnizip
  module Formats
    RSpec.describe "Integration Tests" do
      describe "CPIO round-trip" do
        let(:test_files) do
          {
            "file1.txt" => "Hello, World!",
            "file2.txt" => "Another file content",
          }
        end

        it "writes and reads CPIO archive (newc format)" do
          Dir.mktmpdir do |source_dir|
            # Create test files
            test_files.each do |path, content|
              full_path = File.join(source_dir, path)
              FileUtils.mkdir_p(File.dirname(full_path))
              File.write(full_path, content)
            end

            Tempfile.create(%w[test .cpio]) do |temp|
              temp_path = temp.path
              temp.close

              # Write CPIO
              writer = Cpio::Writer.new(temp_path, format: :newc)
              test_files.each_key do |path|
                writer.add_file(File.join(source_dir, path), path)
              end
              writer.write

              # Read back
              reader = Cpio::Reader.new(temp_path)
              reader.open
              entries = reader.list # Use list to exclude TRAILER

              expect(entries.map(&:name)).to contain_exactly(*test_files.keys)
              test_files.each do |path, expected_content|
                entry = entries.find { |e| e.name == path }
                expect(entry).not_to be_nil
                expect(entry.data).to eq(expected_content)
              end
            end
          end
        end

        it "creates and extracts CPIO with directories" do
          Dir.mktmpdir do |source_dir|
            # Create test directory
            test_dir = File.join(source_dir, "mydir")
            FileUtils.mkdir_p(test_dir)
            File.write(File.join(test_dir, "file.txt"), "content")

            Tempfile.create(%w[test .cpio]) do |temp|
              temp_path = temp.path
              temp.close

              # Write CPIO with directories
              writer = Cpio::Writer.new(temp_path, format: :newc)
              writer.add_directory(test_dir, cpio_path: "mydir",
                                             recursive: true)
              writer.write

              # Read back and verify
              reader = Cpio::Reader.new(temp_path)
              reader.open
              entry_names = reader.list.map(&:name) # Use list to exclude TRAILER
              expect(entry_names).to include("mydir")
              expect(entry_names).to include("mydir/file.txt")
            end
          end
        end
      end

      describe "OLE round-trip" do
        it "writes and reads OLE file with simple content" do
          io = StringIO.new("".b)

          # Write OLE
          ole = Ole::Storage.new(io)
          root = ole.root

          file1 = Ole::Dirent.create(ole, type: :file, name: "test.txt")
          root << file1
          file1.open("w") { |f| f.write("Hello, OLE!") }

          ole.flush
          ole.close

          # Read back
          io.rewind
          ole2 = Ole::Storage.new(io)

          expect(ole2.root.name).to eq("Root Entry")
          expect(ole2.exists?("test.txt")).to be true
          expect(ole2.read("test.txt")).to eq("Hello, OLE!")

          ole2.close
        end

        it "writes and reads OLE file with nested directories" do
          io = StringIO.new("".b)

          # Write OLE with nested structure
          ole = Ole::Storage.new(io)
          root = ole.root

          # Create directory
          dir1 = Ole::Dirent.create(ole, type: :dir, name: "subdir")
          root << dir1

          # Create file in directory
          file1 = Ole::Dirent.create(ole, type: :file, name: "nested.txt")
          dir1 << file1
          file1.open("w") { |f| f.write("Nested content!") }

          # Create file in root
          file2 = Ole::Dirent.create(ole, type: :file, name: "root.txt")
          root << file2
          file2.open("w") { |f| f.write("Root content!") }

          ole.flush
          ole.close

          # Read back
          io.rewind
          ole2 = Ole::Storage.new(io)

          expect(ole2.exists?("root.txt")).to be true
          expect(ole2.read("root.txt")).to eq("Root content!")
          expect(ole2.directory?("subdir")).to be true
          expect(ole2.exists?("subdir/nested.txt")).to be true
          expect(ole2.read("subdir/nested.txt")).to eq("Nested content!")

          ole2.close
        end

        it "writes and reads large files (using BBAT)" do
          io = StringIO.new("".b)
          large_content = "X" * 5000 # > 4096 bytes threshold

          # Write OLE with large file
          ole = Ole::Storage.new(io)
          root = ole.root

          file1 = Ole::Dirent.create(ole, type: :file, name: "large.bin")
          root << file1
          file1.open("w") { |f| f.write(large_content) }

          ole.flush
          ole.close

          # Read back
          io.rewind
          ole2 = Ole::Storage.new(io)

          expect(ole2.read("large.bin")).to eq(large_content)

          ole2.close
        end

        it "modifies existing OLE file" do
          io = StringIO.new("".b)

          # Create initial file
          ole = Ole::Storage.new(io)
          root = ole.root

          file1 = Ole::Dirent.create(ole, type: :file, name: "modify.txt")
          root << file1
          file1.open("w") { |f| f.write("Original content") }

          ole.flush
          ole.close

          # Modify file
          io.rewind
          ole2 = Ole::Storage.new(io)
          ole2.root.children.first.open("w") { |f| f.write("Modified content") }
          ole2.flush
          ole2.close

          # Read back modified content
          io.rewind
          ole3 = Ole::Storage.new(io)
          expect(ole3.read("modify.txt")).to eq("Modified content")
          ole3.close
        end
      end

      describe "RPM round-trip" do
        it "writes and reads RPM package with gzip compression" do
          round_trip_rpm(:gzip)
        end

        it "writes and reads RPM package with bzip2 compression" do
          round_trip_rpm(:bzip2)
        end

        it "writes and reads RPM package with xz compression" do
          round_trip_rpm(:xz)
        end

        it "writes and reads RPM package with zstd compression" do
          round_trip_rpm(:zstd)
        end

        def round_trip_rpm(compression)
          Tempfile.create(%w[test .rpm]) do |temp|
            temp_path = temp.path
            temp.close

            # Write RPM
            writer = Rpm::Writer.new(
              name: "test-pkg",
              version: "1.0.0",
              release: "1",
              arch: "noarch",
              compression: compression,
              summary: "Test package",
              description: "A test package for round-trip testing",
              license: "MIT",
            )

            writer.add_file("/usr/bin/test-app", "#!/bin/bash\necho Hello",
                            mode: 0o755)
            writer.add_directory("/etc/test-pkg")
            writer.add_file("/etc/test-pkg/config.conf", "setting=value\n",
                            mode: 0o644)

            writer.write(temp_path)

            # Read back
            reader = Rpm::Reader.new(temp_path)
            reader.open

            expect(reader.name).to eq("test-pkg")
            expect(reader.version).to eq("1.0.0")
            expect(reader.release).to eq("1")
            expect(reader.architecture).to eq("noarch")
            expect(reader.payload_compressor).to eq(compression.to_s)
            expect(reader.files).to include("/etc/test-pkg", "/usr/bin/test-app",
                                            "/etc/test-pkg/config.conf")

            reader.close
          end
        end

        it "writes RPM and extracts payload" do
          Tempfile.create(%w[test .rpm]) do |rpm_temp|
            Dir.mktmpdir do |extract_dir|
              rpm_path = rpm_temp.path
              rpm_temp.close

              # Write RPM
              writer = Rpm::Writer.new(
                name: "extract-test",
                version: "1.0.0",
                release: "1",
                compression: :gzip,
              )

              writer.add_file("/usr/bin/hello", "#!/bin/sh\necho Hello World",
                              mode: 0o755)
              writer.add_directory("/var/lib/app")
              writer.add_file("/var/lib/app/data.txt", "Application data")

              writer.write(rpm_path)

              # Extract
              Rpm.extract(rpm_path, extract_dir)

              # Verify extracted files
              expect(File.exist?(File.join(extract_dir,
                                           "usr/bin/hello"))).to be true
              expect(File.read(File.join(extract_dir, "usr/bin/hello")))
                .to eq("#!/bin/sh\necho Hello World")
              expect(File.stat(File.join(extract_dir,
                                         "usr/bin/hello")).mode & 0o111)
                .not_to eq(0) # Executable

              expect(File.directory?(File.join(extract_dir,
                                               "var/lib/app"))).to be true
              expect(File.read(File.join(extract_dir, "var/lib/app/data.txt")))
                .to eq("Application data")
            end
          end
        end
      end

      describe "Format compatibility" do
        it "reads reference RPM fixtures" do
          fixture_path = "spec/fixtures/rpm/example-1.0-1.x86_64.rpm"
          skip "Fixture not found" unless File.exist?(fixture_path)

          reader = Rpm::Reader.new(fixture_path)
          reader.open

          expect(reader.name).to eq("example")
          expect(reader.version).to eq("1.0")
          expect(reader.release).to eq("1")
          expect(reader.architecture).to eq("x86_64")

          reader.close
        end

        it "reads reference OLE fixtures" do
          fixture_path = "spec/fixtures/ole/oleWithDirs.ole"
          skip "Fixture not found" unless File.exist?(fixture_path)

          Ole::Storage.open(fixture_path) do |ole|
            expect(ole.root).not_to be_nil
            expect(ole.root.children).not_to be_empty
          end
        end

        it "reads Word document OLE fixture" do
          fixture_path = "spec/fixtures/ole/test_word_6.doc"
          skip "Fixture not found" unless File.exist?(fixture_path)

          Ole::Storage.open(fixture_path) do |ole|
            expect(ole.root).not_to be_nil
            # Word documents should have a WordDocument stream
            expect(ole.exists?("WordDocument")).to be true
          end
        end
      end
    end
  end
end
