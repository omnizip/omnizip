# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Omnizip::Profile do
  before do
    # Reset profile registry for each test (only for top-level Profile tests)
    Omnizip::Profile.reset! if described_class == Omnizip::Profile
  end

  describe ".registry" do
    it "returns a ProfileRegistry instance" do
      expect(described_class.registry).to be_a(Omnizip::Profile::ProfileRegistry)
    end

    it "registers built-in profiles" do
      expect(described_class.registry.names).to include(
        :fast, :balanced, :maximum, :text, :binary, :archive
      )
    end

    it "returns the same registry instance" do
      registry1 = described_class.registry
      registry2 = described_class.registry
      expect(registry1).to be(registry2)
    end
  end

  describe ".get" do
    it "returns a profile by name" do
      profile = described_class.get(:fast)
      expect(profile).to be_a(Omnizip::Profile::CompressionProfile)
      expect(profile.name).to eq(:fast)
    end

    it "returns nil for unknown profile" do
      expect(described_class.get(:unknown)).to be_nil
    end
  end

  describe ".list" do
    it "returns all profile names" do
      names = described_class.list
      expect(names).to include(:fast, :balanced, :maximum, :text, :binary,
                               :archive)
    end
  end

  describe ".define" do
    it "creates a custom profile" do
      profile = described_class.define(:custom) do |p|
        p.algorithm = :lzma2
        p.level = 7
        p.description = "Custom profile"
      end

      expect(profile.name).to eq(:custom)
      expect(profile.algorithm).to eq(:lzma2)
      expect(profile.level).to eq(7)
    end

    it "extends an existing profile" do
      profile = described_class.define(:my_fast, base: :fast) do |p|
        p.level = 2
        p.description = "Custom fast"
      end

      expect(profile.algorithm).to eq(:deflate)
      expect(profile.level).to eq(2)
    end

    it "registers the custom profile" do
      described_class.define(:custom) do |p|
        p.algorithm = :lzma
        p.level = 5
      end

      expect(described_class.get(:custom)).not_to be_nil
    end
  end

  describe ".for_file_type" do
    it "returns text profile for text MIME types" do
      profile = described_class.for_file_type("text/plain")
      expect(profile.name).to eq(:text)
    end

    it "returns binary profile for executable MIME types" do
      profile = described_class.for_file_type("application/x-executable")
      expect(profile.name).to eq(:binary)
    end

    it "returns archive profile for archive MIME types" do
      profile = described_class.for_file_type("application/zip")
      expect(profile.name).to eq(:archive)
    end

    it "handles symbol categories" do
      profile = described_class.for_file_type(:text)
      expect(profile.name).to eq(:text)
    end

    it "handles executable symbol" do
      profile = described_class.for_file_type(:executable)
      expect(profile.name).to eq(:binary)
    end

    it "handles archive symbol" do
      profile = described_class.for_file_type(:archive)
      expect(profile.name).to eq(:archive)
    end
  end

  describe "built-in profiles" do
    describe "FastProfile" do
      let(:profile) { described_class.get(:fast) }

      it "uses deflate algorithm" do
        expect(profile.algorithm).to eq(:deflate)
      end

      it "uses level 1" do
        expect(profile.level).to eq(1)
      end

      it "does not use solid compression" do
        expect(profile.solid).to be false
      end

      it "is suitable for all file types" do
        expect(profile.suitable_for?("text/plain")).to be true
        expect(profile.suitable_for?("application/zip")).to be true
        expect(profile.suitable_for?("image/png")).to be true
      end
    end

    describe "BalancedProfile" do
      let(:profile) { described_class.get(:balanced) }

      it "uses deflate algorithm" do
        expect(profile.algorithm).to eq(:deflate)
      end

      it "uses level 6" do
        expect(profile.level).to eq(6)
      end

      it "does not use solid compression" do
        expect(profile.solid).to be false
      end
    end

    describe "MaximumProfile" do
      let(:profile) { described_class.get(:maximum) }

      it "uses lzma2 algorithm" do
        expect(profile.algorithm).to eq(:lzma2)
      end

      it "uses level 9" do
        expect(profile.level).to eq(9)
      end

      it "uses solid compression" do
        expect(profile.solid).to be true
      end

      it "uses auto filter" do
        expect(profile.filter).to eq(:auto)
      end
    end

    describe "TextProfile" do
      let(:profile) { described_class.get(:text) }

      it "uses ppmd7 algorithm" do
        expect(profile.algorithm).to eq(:ppmd7)
      end

      it "uses level 6" do
        expect(profile.level).to eq(6)
      end

      it "is suitable for text files" do
        expect(profile.suitable_for?("text/plain")).to be true
        expect(profile.suitable_for?("text/html")).to be true
        expect(profile.suitable_for?("application/json")).to be true
      end

      it "is not suitable for binary files" do
        expect(profile.suitable_for?("application/x-executable")).to be false
        expect(profile.suitable_for?("application/zip")).to be false
      end
    end

    describe "BinaryProfile" do
      let(:profile) { described_class.get(:binary) }

      it "uses lzma2 algorithm" do
        expect(profile.algorithm).to eq(:lzma2)
      end

      it "uses bcj_x86 filter" do
        expect(profile.filter).to eq(:bcj_x86)
      end

      it "is suitable for executables" do
        expect(profile.suitable_for?("application/x-executable")).to be true
        expect(profile.suitable_for?("application/x-elf")).to be true
      end

      it "is not suitable for text files" do
        expect(profile.suitable_for?("text/plain")).to be false
      end
    end

    describe "ArchiveProfile" do
      let(:profile) { described_class.get(:archive) }

      it "uses store algorithm" do
        expect(profile.algorithm).to eq(:store)
      end

      it "uses level 0" do
        expect(profile.level).to eq(0)
      end

      it "is suitable for compressed files" do
        expect(profile.suitable_for?("application/zip")).to be true
        expect(profile.suitable_for?("application/x-7z-compressed")).to be true
        expect(profile.suitable_for?("application/gzip")).to be true
      end

      it "is suitable for media files" do
        expect(profile.suitable_for?("image/png")).to be true
        expect(profile.suitable_for?("video/mp4")).to be true
        expect(profile.suitable_for?("audio/mpeg")).to be true
      end

      it "is not suitable for text files" do
        expect(profile.suitable_for?("text/plain")).to be false
      end
    end
  end

  describe "profile application" do
    it "applies profile settings to options" do
      profile = described_class.get(:fast)
      options = {}

      result = profile.apply_to(options)

      expect(result[:algorithm]).to eq(:deflate)
      expect(result[:level]).to eq(1)
      expect(result[:solid]).to be false
    end

    it "preserves existing options" do
      profile = described_class.get(:fast)
      options = { custom: "value" }

      result = profile.apply_to(options)

      expect(result[:custom]).to eq("value")
    end
  end

  describe Omnizip::Profile::ProfileRegistry do
    let(:registry) { Omnizip::Profile::ProfileRegistry.new }
    let(:profile) do
      Omnizip::Profile::FastProfile.new
    end

    describe "#register" do
      it "registers a profile" do
        registry.register(profile)
        expect(registry.get(:fast)).to eq(profile)
      end

      it "raises error for duplicate registration" do
        registry.register(profile)
        expect do
          registry.register(profile)
        end.to raise_error(ArgumentError, /already registered/)
      end

      it "raises error for non-profile object" do
        expect do
          registry.register("not a profile")
        end.to raise_error(ArgumentError, /must be a CompressionProfile/)
      end
    end

    describe "#register!" do
      it "replaces existing profile" do
        registry.register(profile)

        # Create a new custom profile with same name
        custom = Omnizip::Profile::CustomProfile.new(
          name: :fast,
          algorithm: :lzma,
          level: 5,
          description: "Replacement",
        )

        registry.register!(custom)
        expect(registry.get(:fast)).to eq(custom)
      end
    end

    describe "#unregister" do
      it "removes a profile" do
        registry.register(profile)
        registry.unregister(:fast)
        expect(registry.get(:fast)).to be_nil
      end
    end

    describe "#registered?" do
      it "returns true for registered profile" do
        registry.register(profile)
        expect(registry.registered?(:fast)).to be true
      end

      it "returns false for unregistered profile" do
        expect(registry.registered?(:unknown)).to be false
      end
    end

    describe "#suitable_for" do
      it "returns suitable profiles for MIME type" do
        text_profile = Omnizip::Profile::TextProfile.new
        registry.register(text_profile)

        suitable = registry.suitable_for("text/plain")

        expect(suitable).to include(text_profile)
      end

      it "returns suitable profiles for executable MIME type" do
        binary_profile = Omnizip::Profile::BinaryProfile.new
        registry.register(binary_profile)

        suitable = registry.suitable_for("application/x-executable")

        expect(suitable).to include(binary_profile)
      end

      it "returns suitable profiles for archive MIME type" do
        archive_profile = Omnizip::Profile::ArchiveProfile.new
        registry.register(archive_profile)

        suitable = registry.suitable_for("application/zip")

        expect(suitable).to include(archive_profile)
      end
    end
  end

  describe Omnizip::Profile::ProfileDetector do
    let(:detector) { Omnizip::Profile::ProfileDetector.new(Omnizip::Profile.registry) }

    describe "#detect" do
      it "detects profile for a text file" do
        Tempfile.create(["test", ".txt"]) do |file|
          file.write("Hello, world!")
          file.flush

          profile = detector.detect(file.path)
          expect(profile).to be_a(Omnizip::Profile::CompressionProfile)
          # Marcel may detect simple text as octet-stream (binary profile)
          # or as text (text profile), both are acceptable
          expect(profile.name).to match(/text|binary|balanced/)
        end
      end

      it "detects profile for an archive file" do
        Tempfile.create(["test", ".zip"]) do |file|
          file.write("PK\x03\x04")
          file.write("zip content")
          file.flush

          profile = detector.detect(file.path)
          expect(profile).to be_a(Omnizip::Profile::CompressionProfile)
          # Archives should get archive profile
          expect(profile.name).to eq(:archive)
        end
      end

      it "returns fallback for nonexistent file" do
        profile = detector.detect("/nonexistent/file.txt")
        expect(profile.name).to eq(:balanced)
      end

      it "uses custom fallback" do
        profile = detector.detect("/nonexistent/file.txt", fallback: :fast)
        expect(profile.name).to eq(:fast)
      end
    end

    describe "#detect_mime_type" do
      it "detects MIME type for existing file" do
        Tempfile.create(["test", ".txt"]) do |file|
          file.write("Hello, world!")
          file.flush

          mime_type = detector.detect_mime_type(file.path)
          # Marcel may detect as text/plain or application/octet-stream
          expect(mime_type).to match(/text\/plain|application\/octet-stream/)
        end
      end

      it "returns nil for non-existent file" do
        mime_type = detector.detect_mime_type("/nonexistent/file.txt")
        expect(mime_type).to be_nil
      end
    end

    describe "#find_suitable_profiles" do
      it "finds suitable profiles for text MIME type" do
        suitable = detector.find_suitable_profiles("text/plain")
        expect(suitable).not_to be_empty
        expect(suitable.map(&:name)).to include(:text)
      end

      it "finds suitable profiles for executable MIME type" do
        suitable = detector.find_suitable_profiles("application/x-executable")
        expect(suitable).not_to be_empty
        expect(suitable.map(&:name)).to include(:binary)
      end

      it "returns empty array for nil MIME type" do
        suitable = detector.find_suitable_profiles(nil)
        expect(suitable).to be_empty
      end
    end
  end

  describe Omnizip::Profile::CustomProfile do
    describe "builder" do
      it "builds a custom profile" do
        builder = Omnizip::Profile::CustomProfile::Builder.new(:test)
        builder.algorithm = :lzma2
        builder.level = 7
        builder.description = "Test profile"

        profile = builder.build

        expect(profile.name).to eq(:test)
        expect(profile.algorithm).to eq(:lzma2)
        expect(profile.level).to eq(7)
      end

      it "validates profile settings" do
        builder = Omnizip::Profile::CustomProfile::Builder.new(:test)
        builder.level = 10 # Invalid level

        expect { builder.valid? }.to raise_error(ArgumentError)
      end

      it "inherits from base profile" do
        base = Omnizip::Profile.get(:fast)
        builder = Omnizip::Profile::CustomProfile::Builder.new(:test, base)

        expect(builder.algorithm).to eq(:deflate)
        expect(builder.level).to eq(1)
      end
    end
  end
end
