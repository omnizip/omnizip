require "tmpdir"

RSpec.describe Omnizip::Formats::SevenZip::Writer, "non-solid mode" do
  it "compresses each file independently (LZMA2)" do
    Dir.mktmpdir("omnizip_ns7z") do |tmp|
      src = File.join(tmp, "big.txt")
      File.binwrite(src, "non-solid compression fixture " * 1000)
      archive = File.join(tmp, "ns.7z")

      writer = described_class.new(archive, solid: false)
      writer.add_file(src, "big.txt")
      writer.write

      expect(File.size(archive)).to be < 10_000

      reader = Omnizip::Formats::SevenZip::Reader.new(archive)
      entry = reader.list_files.first
      expect(entry.compressed_size).to be < entry.size

      out = File.join(tmp, "out.txt")
      reader.extract_entry("big.txt", out)
      expect(File.binread(out)).to eq(File.binread(src))
    end
  end

  it "extracts every file of a multi-file non-solid archive byte-exactly" do
    Dir.mktmpdir("omnizip_ns7z_multi") do |tmp|
      a = File.join(tmp, "a.txt")
      File.binwrite(a, "A" * 20_000)
      b = File.join(tmp, "b.bin")
      File.binwrite(b, (0..255).map(&:chr).join * 40)
      c = File.join(tmp, "c.txt")
      File.write(c, "short")
      archive = File.join(tmp, "m.7z")

      writer = described_class.new(archive, solid: false)
      writer.add_file(a, "a.txt")
      writer.add_file(b, "b.bin")
      writer.add_file(c, "c.txt")
      writer.write

      reader = Omnizip::Formats::SevenZip::Reader.new(archive)
      out = File.join(tmp, "out")
      reader.extract_all(out)

      expect(File.binread(File.join(out, "a.txt"))).to eq(File.binread(a))
      expect(File.binread(File.join(out, "b.bin"))).to eq(File.binread(b))
      expect(File.read(File.join(out, "c.txt"))).to eq("short")
    end
  end
end
