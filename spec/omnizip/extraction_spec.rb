# frozen_string_literal: true

require "spec_helper"
require "omnizip/extraction"
require "omnizip/models/extraction_rule"
require "omnizip/models/match_result"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Extraction do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_dir) { File.join(temp_dir, "output") }

  after do
    FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
  end

  # Mock archive entry class
  class MockEntry
    attr_reader :name, :size

    def initialize(name, content = "test content", size = nil)
      @name = name
      @content = content
      @size = size || content.bytesize
    end

    def read
      @content
    end
  end

  # Mock archive class
  class MockArchive
    attr_reader :entries

    def initialize(entries)
      @entries = entries.map do |name, content|
        MockEntry.new(name, content || "test")
      end
    end

    def read(entry)
      entry.read
    end
  end

  describe Omnizip::Extraction::GlobPattern do
    describe "#match?" do
      it "matches simple wildcard patterns" do
        pattern = described_class.new("*.txt")
        expect(pattern.match?("file.txt")).to be true
        expect(pattern.match?("file.rb")).to be false
        expect(pattern.match?("dir/file.txt")).to be false
      end

      it "matches recursive wildcard patterns" do
        pattern = described_class.new("**/*.txt")
        expect(pattern.match?("file.txt")).to be true
        expect(pattern.match?("dir/file.txt")).to be true
        expect(pattern.match?("dir/subdir/file.txt")).to be true
        expect(pattern.match?("file.rb")).to be false
      end

      it "matches question mark patterns" do
        pattern = described_class.new("file?.txt")
        expect(pattern.match?("file1.txt")).to be true
        expect(pattern.match?("fileA.txt")).to be true
        expect(pattern.match?("file.txt")).to be false
        expect(pattern.match?("file12.txt")).to be false
      end

      it "matches character class patterns" do
        pattern = described_class.new("file[123].txt")
        expect(pattern.match?("file1.txt")).to be true
        expect(pattern.match?("file2.txt")).to be true
        expect(pattern.match?("file4.txt")).to be false
      end

      it "matches negated character class patterns" do
        pattern = described_class.new("file[!123].txt")
        expect(pattern.match?("file4.txt")).to be true
        expect(pattern.match?("fileA.txt")).to be true
        expect(pattern.match?("file1.txt")).to be false
      end

      it "matches brace expansion patterns" do
        pattern = described_class.new("file.{txt,md,rb}")
        expect(pattern.match?("file.txt")).to be true
        expect(pattern.match?("file.md")).to be true
        expect(pattern.match?("file.rb")).to be true
        expect(pattern.match?("file.py")).to be false
      end

      it "matches complex nested patterns" do
        pattern = described_class.new("src/**/*.{rb,js}")
        expect(pattern.match?("src/app.rb")).to be true
        expect(pattern.match?("src/lib/util.js")).to be true
        expect(pattern.match?("src/test/spec.rb")).to be true
        expect(pattern.match?("src/README.md")).to be false
      end

      it "matches paths with directories" do
        pattern = described_class.new("**/test/**/*.rb")
        expect(pattern.match?("test/file.rb")).to be true
        expect(pattern.match?("src/test/file.rb")).to be true
        expect(pattern.match?("src/test/unit/file.rb")).to be true
        expect(pattern.match?("src/lib/file.rb")).to be false
      end
    end
  end

  describe Omnizip::Extraction::RegexPattern do
    describe "#match?" do
      it "matches regex patterns" do
        pattern = described_class.new(/\.log$/)
        expect(pattern.match?("app.log")).to be true
        expect(pattern.match?("error.log")).to be true
        expect(pattern.match?("app.txt")).to be false
      end

      it "matches complex regex patterns" do
        pattern = described_class.new(/^src\/.*\.rb$/)
        expect(pattern.match?("src/app.rb")).to be true
        expect(pattern.match?("src/lib/util.rb")).to be true
        expect(pattern.match?("test/spec.rb")).to be false
      end

      it "supports case-insensitive matching" do
        pattern = described_class.new(/\.TXT$/i)
        expect(pattern.match?("file.txt")).to be true
        expect(pattern.match?("file.TXT")).to be true
        expect(pattern.match?("file.Txt")).to be true
      end
    end
  end

  describe Omnizip::Extraction::PredicatePattern do
    describe "#match?" do
      it "matches using custom predicate" do
        pattern = described_class.new("large files") do |entry|
          entry.size > 100
        end

        large_entry = MockEntry.new("large.bin", "x" * 200, 200)
        small_entry = MockEntry.new("small.txt", "x" * 50, 50)

        expect(pattern.match?(large_entry)).to be true
        expect(pattern.match?(small_entry)).to be false
      end

      it "handles predicate errors gracefully" do
        pattern = described_class.new("error prone") do |_entry|
          raise StandardError, "Test error"
        end

        entry = MockEntry.new("test.txt")
        expect(pattern.match?(entry)).to be false
      end
    end
  end

  describe Omnizip::Extraction::PatternMatcher do
    it "automatically detects glob patterns" do
      matcher = described_class.new("*.txt")
      expect(matcher.match?("file.txt")).to be true
      expect(matcher.match?("file.rb")).to be false
    end

    it "automatically detects regex patterns" do
      matcher = described_class.new(/\.txt$/)
      expect(matcher.match?("file.txt")).to be true
      expect(matcher.match?("file.rb")).to be false
    end

    it "automatically detects predicate patterns" do
      matcher = described_class.new(proc { |name| name.include?("test") })
      expect(matcher.match?("test_file.rb")).to be true
      expect(matcher.match?("app.rb")).to be false
    end

    describe "#match_all" do
      it "filters array of filenames" do
        matcher = described_class.new("*.txt")
        files = ["a.txt", "b.rb", "c.txt", "d.md"]
        expect(matcher.match_all(files)).to eq(["a.txt", "c.txt"])
      end
    end
  end

  describe Omnizip::Extraction::FilterChain do
    it "includes files matching include patterns" do
      chain = described_class.new
        .include_pattern("*.txt")
        .include_pattern("*.md")

      expect(chain.match?("file.txt")).to be true
      expect(chain.match?("file.md")).to be true
      expect(chain.match?("file.rb")).to be false
    end

    it "excludes files matching exclude patterns" do
      chain = described_class.new
        .include_pattern("**/*.rb")
        .exclude_pattern("**/test/**")

      expect(chain.match?("src/app.rb")).to be true
      expect(chain.match?("src/lib/util.rb")).to be true
      expect(chain.match?("test/spec.rb")).to be false
      expect(chain.match?("src/test/helper.rb")).to be false
    end

    it "combines include and exclude predicates" do
      chain = described_class.new
        .include { |entry| entry.name.end_with?(".rb") }
        .exclude { |entry| entry.name.include?("test") }

      expect(chain.match?(MockEntry.new("app.rb"))).to be true
      expect(chain.match?(MockEntry.new("test_app.rb"))).to be false
      expect(chain.match?(MockEntry.new("app.txt"))).to be false
    end

    it "includes all files when no filters specified" do
      chain = described_class.new
      expect(chain.match?("any.file")).to be true
    end

    it "filters array of entries" do
      chain = described_class.new
        .include_pattern("*.txt")
        .exclude_pattern("*test*")

      entries = [
        MockEntry.new("file.txt"),
        MockEntry.new("test.txt"),
        MockEntry.new("file.rb"),
        MockEntry.new("readme.txt")
      ]

      filtered = chain.filter(entries)
      expect(filtered.map(&:name)).to eq(["file.txt", "readme.txt"])
    end
  end

  describe Omnizip::Extraction::SelectiveExtractor do
    let(:archive) do
      MockArchive.new([
        ["README.md", "readme content"],
        ["src/app.rb", "ruby code"],
        ["src/lib/util.rb", "utility code"],
        ["test/spec.rb", "test code"],
        ["docs/guide.txt", "guide text"],
        ["data.json", "json data"]
      ])
    end

    describe "#list_matches" do
      it "lists files matching glob pattern" do
        filter = Omnizip::Extraction::PatternMatcher.new("*.md")
        extractor = described_class.new(archive, filter)
        matches = extractor.list_matches

        expect(matches.map(&:name)).to eq(["README.md"])
      end

      it "lists files matching recursive glob pattern" do
        filter = Omnizip::Extraction::PatternMatcher.new("**/*.rb")
        extractor = described_class.new(archive, filter)
        matches = extractor.list_matches

        expect(matches.map(&:name)).to match_array([
          "src/app.rb",
          "src/lib/util.rb",
          "test/spec.rb"
        ])
      end

      it "lists files matching filter chain" do
        filter = Omnizip::Extraction::FilterChain.new
          .include_pattern("**/*.rb")
          .exclude_pattern("**/test/**")

        extractor = described_class.new(archive, filter)
        matches = extractor.list_matches

        expect(matches.map(&:name)).to match_array([
          "src/app.rb",
          "src/lib/util.rb"
        ])
      end
    end

    describe "#count_matches" do
      it "counts matching files" do
        filter = Omnizip::Extraction::PatternMatcher.new("**/*.rb")
        extractor = described_class.new(archive, filter)

        expect(extractor.count_matches).to eq(3)
      end
    end

    describe "#extract_to_memory" do
      it "extracts matching files to hash" do
        filter = Omnizip::Extraction::PatternMatcher.new("*.{md,json}")
        extractor = described_class.new(archive, filter)
        result = extractor.extract_to_memory

        expect(result).to include(
          "README.md" => "readme content",
          "data.json" => "json data"
        )
      end
    end

    describe "#extract" do
      it "extracts matching files to disk" do
        FileUtils.mkdir_p(output_dir)
        filter = Omnizip::Extraction::PatternMatcher.new("*.md")
        extractor = described_class.new(archive, filter)

        paths = extractor.extract(output_dir)

        expect(paths).to eq([File.join(output_dir, "README.md")])
        expect(File.read(File.join(output_dir, "README.md"))).to eq("readme content")
      end

      it "preserves directory structure by default" do
        FileUtils.mkdir_p(output_dir)
        filter = Omnizip::Extraction::PatternMatcher.new("**/*.rb")
        extractor = described_class.new(archive, filter)

        extractor.extract(output_dir)

        expect(File).to exist(File.join(output_dir, "src/app.rb"))
        expect(File).to exist(File.join(output_dir, "src/lib/util.rb"))
        expect(File).to exist(File.join(output_dir, "test/spec.rb"))
      end

      it "flattens paths when requested" do
        FileUtils.mkdir_p(output_dir)
        filter = Omnizip::Extraction::PatternMatcher.new("**/*.rb")
        extractor = described_class.new(archive, filter)

        extractor.extract(output_dir, flatten: true)

        expect(File).to exist(File.join(output_dir, "app.rb"))
        expect(File).to exist(File.join(output_dir, "util.rb"))
        expect(File).to exist(File.join(output_dir, "spec.rb"))
      end
    end

    describe "#match_result" do
      it "returns match statistics" do
        filter = Omnizip::Extraction::PatternMatcher.new("**/*.rb")
        extractor = described_class.new(archive, filter)
        result = extractor.match_result

        expect(result.count).to eq(3)
        expect(result.total_scanned).to eq(6)
        expect(result.match_rate).to be_within(0.01).of(0.5)
      end
    end
  end

  describe Omnizip::Models::ExtractionRule do
    it "stores patterns and predicates" do
      rule = described_class.new(
        patterns: ["*.txt", /\.log$/],
        predicates: [proc { |e| e.size > 100 }]
      )

      expect(rule.patterns).to eq(["*.txt", /\.log$/])
      expect(rule.predicates.size).to eq(1)
    end

    it "supports chaining pattern additions" do
      rule = described_class.new
        .add_pattern("*.txt")
        .add_pattern("*.md")

      expect(rule.patterns).to eq(["*.txt", "*.md"])
    end

    it "supports adding predicates" do
      rule = described_class.new
        .add_predicate { |e| e.size > 100 }

      expect(rule.predicates.size).to eq(1)
    end

    it "provides default options" do
      rule = described_class.new
      expect(rule.preserve_paths?).to be true
      expect(rule.flatten?).to be false
      expect(rule.overwrite?).to be false
    end
  end

  describe Omnizip::Models::MatchResult do
    it "tracks matches and statistics" do
      result = described_class.new("*.txt")
        .add_match(MockEntry.new("a.txt"))
        .add_match(MockEntry.new("b.txt"))
        .increment_scanned(5)

      expect(result.count).to eq(2)
      expect(result.total_scanned).to eq(5)
      expect(result.match_rate).to be_within(0.01).of(0.4)
      expect(result.match_percentage).to be_within(0.1).of(40.0)
    end

    it "supports iteration" do
      matches = [MockEntry.new("a.txt"), MockEntry.new("b.txt")]
      result = described_class.new("*.txt", matches: matches, total_scanned: 10)

      collected = []
      result.each { |m| collected << m }

      expect(collected).to eq(matches)
    end
  end

  describe "Integration" do
    let(:archive) do
      MockArchive.new([
        ["README.md", "readme"],
        ["LICENSE", "license"],
        ["src/app.rb", "app"],
        ["src/lib/util.rb", "util"],
        ["src/lib/helper.rb", "helper"],
        ["test/app_spec.rb", "spec"],
        ["test/util_spec.rb", "spec"],
        ["docs/guide.txt", "guide"],
        ["docs/api.md", "api"],
        ["config.yml", "config"]
      ])
    end

    it "extracts using module-level API" do
      FileUtils.mkdir_p(output_dir)
      paths = Omnizip::Extraction.extract_matching(
        archive,
        "*.md",
        output_dir
      )

      expect(paths.size).to eq(1)
      expect(File).to exist(File.join(output_dir, "README.md"))
    end

    it "extracts multiple patterns" do
      FileUtils.mkdir_p(output_dir)
      paths = Omnizip::Extraction.extract_matching(
        archive,
        ["*.md", "*.yml"],
        output_dir
      )

      expect(paths.size).to eq(2)
    end

    it "lists matches without extracting" do
      matches = Omnizip::Extraction.list_matching(archive, "**/*.rb")
      expect(matches.map(&:name)).to match_array([
        "src/app.rb",
        "src/lib/util.rb",
        "src/lib/helper.rb",
        "test/app_spec.rb",
        "test/util_spec.rb"
      ])
    end

    it "counts matches" do
      count = Omnizip::Extraction.count_matching(archive, "**/*.rb")
      expect(count).to eq(5)
    end

    it "extracts to memory" do
      files = Omnizip::Extraction.extract_to_memory_matching(
        archive,
        "*.{md,yml}"
      )

      expect(files).to include(
        "README.md" => "readme",
        "config.yml" => "config"
      )
    end

    it "extracts with complex filter chain" do
      FileUtils.mkdir_p(output_dir)
      filter = Omnizip::Extraction::FilterChain.new
        .include_pattern("**/*.rb")
        .exclude_pattern("**/test/**")

      paths = Omnizip::Extraction.extract_with_filter(
        archive,
        filter,
        output_dir
      )

      expect(paths.size).to eq(3)
      expect(File).to exist(File.join(output_dir, "src/app.rb"))
      expect(File).not_to exist(File.join(output_dir, "test/app_spec.rb"))
    end
  end
end