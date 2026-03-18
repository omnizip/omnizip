# frozen_string_literal: true

require "fileutils"
require "open-uri"
require "digest/sha2"

namespace :test_files do
  desc "Download Adobe font pack MSI for testing (60MB)"
  task :adobe_msi do
    url = "https://web.archive.org/web/20200816153035/http://ardownload.adobe.com/pub/adobe/reader/win/AcrobatDC/misc/FontPack1902120058_XtdAlf_Lang_DC.msi"
    output_dir = "spec/fixtures/adobe"
    output_path = "#{output_dir}/FontPack1902120058_XtdAlf_Lang_DC.msi"
    expected_sha256 = "b5b9e15791a177715fa5e93ea458f8627cada7ac3218531461cfd35cecef6c24"

    FileUtils.mkdir_p(output_dir)

    if File.exist?(output_path)
      # Verify existing file
      actual_sha256 = Digest::SHA256.file(output_path).hexdigest
      if actual_sha256 == expected_sha256
        puts "Adobe font pack MSI already exists and verified: #{output_path}"
        return
      else
        puts "Existing file has wrong SHA256, re-downloading..."
        File.delete(output_path)
      end
    end

    puts "Downloading Adobe font pack MSI (60MB)..."
    puts "URL: #{url}"

    begin
      URI.open(url, "rb") do |remote|
        File.binwrite(output_path, remote.read)
      end
    rescue OpenURI::HTTPError, Net::OpenTimeout, Errno::ECONNREFUSED => e
      puts "Failed to download: #{e.message}"
      puts "You may need to download manually from:"
      puts "  #{url}"
      puts "And place it at: #{output_path}"
      exit 1
    end

    # Verify SHA256
    actual_sha256 = Digest::SHA256.file(output_path).hexdigest
    if actual_sha256 == expected_sha256
      puts "Downloaded and verified: #{output_path}"
      puts "SHA256: #{actual_sha256}"
    else
      File.delete(output_path)
      puts "SHA256 mismatch!"
      puts "Expected: #{expected_sha256}"
      puts "Got:      #{actual_sha256}"
      exit 1
    end
  end

  desc "Clean up downloaded test files"
  task :clean do
    adobe_dir = "spec/fixtures/adobe"
    if File.directory?(adobe_dir)
      FileUtils.rm_rf(adobe_dir)
      puts "Removed: #{adobe_dir}"
    end
  end
end
