# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::LinkHandler do
  describe ".supported?" do
    it "returns false on Windows" do
      allow(described_class).to receive(:windows_platform?).and_return(true)
      expect(described_class.supported?).to be false
    end

    it "returns true on Unix/macOS" do
      allow(described_class).to receive(:windows_platform?).and_return(false)
      expect(described_class.supported?).to be true
    end
  end

  describe ".symlink_supported?" do
    it "returns true when File.symlink exists and platform is supported" do
      allow(described_class).to receive(:supported?).and_return(true)
      expect(described_class.symlink_supported?).to be(File.respond_to?(:symlink))
    end

    it "returns false when platform is not supported" do
      allow(described_class).to receive(:supported?).and_return(false)
      expect(described_class.symlink_supported?).to be false
    end
  end

  describe ".hardlink_supported?" do
    it "returns true when File.link exists and platform is supported" do
      allow(described_class).to receive(:supported?).and_return(true)
      expect(described_class.hardlink_supported?).to be(File.respond_to?(:link))
    end

    it "returns false when platform is not supported" do
      allow(described_class).to receive(:supported?).and_return(false)
      expect(described_class.hardlink_supported?).to be false
    end
  end

  if RUBY_PLATFORM !~ /mswin|mingw|cygwin/
    describe "Unix/macOS link operations", :unix_only do
      let(:temp_dir) { Dir.mktmpdir }
      let(:target_file) { File.join(temp_dir, "target.txt") }
      let(:symlink_path) { File.join(temp_dir, "symlink") }
      let(:hardlink_path) { File.join(temp_dir, "hardlink") }

      before do
        File.write(target_file, "test content")
      end

      after do
        FileUtils.rm_rf(temp_dir)
      end

      describe ".symlink?" do
        it "returns true for symbolic links" do
          File.symlink(target_file, symlink_path)
          expect(described_class.symlink?(symlink_path)).to be true
        end

        it "returns false for regular files" do
          expect(described_class.symlink?(target_file)).to be false
        end

        it "returns false for directories" do
          dir_path = File.join(temp_dir, "testdir")
          Dir.mkdir(dir_path)
          expect(described_class.symlink?(dir_path)).to be false
        end

        it "returns false for non-existent files" do
          expect(described_class.symlink?("/nonexistent/path")).to be false
        end
      end

      describe ".hardlink?" do
        it "returns true for hard links" do
          File.link(target_file, hardlink_path)
          expect(described_class.hardlink?(hardlink_path)).to be true
        end

        it "returns false for files with only one link" do
          single_file = File.join(temp_dir, "single.txt")
          File.write(single_file, "content")
          expect(described_class.hardlink?(single_file)).to be false
        end

        it "returns false for symbolic links" do
          File.symlink(target_file, symlink_path)
          expect(described_class.hardlink?(symlink_path)).to be false
        end

        it "returns false for non-existent files" do
          expect(described_class.hardlink?("/nonexistent/path")).to be false
        end
      end

      describe ".detect_link" do
        it "returns :symlink for symbolic links" do
          File.symlink(target_file, symlink_path)
          expect(described_class.detect_link(symlink_path)).to eq(:symlink)
        end

        it "returns :hardlink for hard links" do
          File.link(target_file, hardlink_path)
          expect(described_class.detect_link(hardlink_path)).to eq(:hardlink)
        end

        it "returns nil for regular files" do
          expect(described_class.detect_link(target_file)).to be_nil
        end

        it "returns nil for directories" do
          dir_path = File.join(temp_dir, "testdir")
          Dir.mkdir(dir_path)
          expect(described_class.detect_link(dir_path)).to be_nil
        end
      end

      describe ".create_symlink" do
        it "creates a symbolic link" do
          described_class.create_symlink(target_file, symlink_path)
          expect(File.symlink?(symlink_path)).to be true
          expect(File.readlink(symlink_path)).to eq(target_file)
        end

        it "creates parent directories if needed" do
          nested_path = File.join(temp_dir, "nested", "dir", "link")
          described_class.create_symlink(target_file, nested_path)
          expect(File.symlink?(nested_path)).to be true
        end

        it "works with relative paths" do
          described_class.create_symlink("../target.txt", symlink_path)
          expect(File.symlink?(symlink_path)).to be true
        end
      end

      describe ".create_hardlink" do
        it "creates a hard link" do
          described_class.create_hardlink(target_file, hardlink_path)
          expect(File.exist?(hardlink_path)).to be true
          expect(File.stat(hardlink_path).ino).to eq(File.stat(target_file).ino)
        end

        it "creates parent directories if needed" do
          nested_path = File.join(temp_dir, "nested", "dir", "hardlink")
          described_class.create_hardlink(target_file, nested_path)
          expect(File.exist?(nested_path)).to be true
        end

        it "links point to the same content" do
          described_class.create_hardlink(target_file, hardlink_path)
          expect(File.read(hardlink_path)).to eq(File.read(target_file))
        end
      end

      describe ".read_link_target" do
        it "reads the target of a symbolic link" do
          File.symlink(target_file, symlink_path)
          expect(described_class.read_link_target(symlink_path)).to eq(target_file)
        end

        it "handles relative symlink targets" do
          File.symlink("../target.txt", symlink_path)
          expect(described_class.read_link_target(symlink_path)).to eq("../target.txt")
        end

        it "raises error for non-symlinks" do
          expect do
            described_class.read_link_target(target_file)
          end.to raise_error(SystemCallError)
        end
      end

      describe ".inode_number" do
        it "returns inode number for files" do
          inode = described_class.inode_number(target_file)
          expect(inode).to be_a(Integer)
          expect(inode).to eq(File.stat(target_file).ino)
        end

        it "returns same inode for hard links" do
          File.link(target_file, hardlink_path)
          expect(described_class.inode_number(hardlink_path)).to eq(
            described_class.inode_number(target_file)
          )
        end

        it "returns nil for non-existent files" do
          expect(described_class.inode_number("/nonexistent")).to be_nil
        end
      end

      describe ".symbolic_link_from_path" do
        it "creates SymbolicLink from filesystem path" do
          File.symlink(target_file, symlink_path)
          link = described_class.symbolic_link_from_path(symlink_path)

          expect(link).to be_a(Omnizip::LinkHandler::SymbolicLink)
          expect(link.target).to eq(target_file)
          expect(link.path).to eq(symlink_path)
        end

        it "returns nil for regular files" do
          link = described_class.symbolic_link_from_path(target_file)
          expect(link).to be_nil
        end
      end

      describe ".hard_link_from_path" do
        it "creates HardLink from filesystem path" do
          File.link(target_file, hardlink_path)
          link = described_class.hard_link_from_path(hardlink_path, target_file)

          expect(link).to be_a(Omnizip::LinkHandler::HardLink)
          expect(link.target).to eq(target_file)
          expect(link.path).to eq(hardlink_path)
          expect(link.inode).to eq(File.stat(hardlink_path).ino)
        end

        it "returns nil for regular files" do
          single_file = File.join(temp_dir, "single.txt")
          File.write(single_file, "content")
          link = described_class.hard_link_from_path(single_file, target_file)
          expect(link).to be_nil
        end
      end
    end
  else
    describe "Windows platform", :windows_only do
      it "raises error when trying to create symlink" do
        expect do
          described_class.create_symlink("/target", "/link")
        end.to raise_error(Omnizip::Error, /not supported/)
      end

      it "raises error when trying to create hardlink" do
        expect do
          described_class.create_hardlink("/target", "/link")
        end.to raise_error(Omnizip::Error, /not supported/)
      end

      it "raises error when trying to read link target" do
        expect do
          described_class.read_link_target("/link")
        end.to raise_error(Omnizip::Error, /not supported/)
      end
    end
  end
end