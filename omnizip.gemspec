# frozen_string_literal: true

require_relative "lib/omnizip/version"

Gem::Specification.new do |spec|
  spec.name = "omnizip"
  spec.version = Omnizip::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Multi-format compression and extraction library"
  spec.description = <<~DESC
    Omnizip is an extractor/compressor library that implements a comprehensive set
    of data compression algorithms and archive formats, in pure Ruby.
    Supports LZMA, ZIP, 7z, RAR, XZ, CPIO, ISO 9660, PAR and more.
  DESC
  spec.homepage = "https://github.com/riboseinc/omnizip"
  spec.license = "LGPL-2.1-or-later"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(
    %w[git ls-files -z], chdir: __dir__, err: IO::NULL
  ) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .travis
                          .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "base64"
  spec.add_dependency "bindata", "~> 2.4"
  spec.add_dependency "lutaml-model", "~> 0.7"
  spec.add_dependency "marcel", "~> 1.0"
  spec.add_dependency "rexml"
end
