# frozen_string_literal: true

# Build per-platform gems that vendor a prebuilt omnizip-ffi cdylib,
# so `gem install omnizip` gives Rust acceleration with zero
# compilation (parsanol distribution model, adopted 2026-09-21).
#
#   # after downloading the release-binary artifacts:
#   gh release download omnizip-ffi-v0.21.108 -R omnizip/omnizip-rs \
#     -p 'libomnizip_ffi-*.tar.gz' -D artifacts
#   bundle exec rake platform_gems:build DIR=artifacts
#
# Each target tarball maps to one rubygems platform; the built gems
# land in pkg/. The plain `ruby` platform gem keeps shipping without
# a binary (pure-Ruby core; OMNIZIP_NO_RUST=1 disables the tier).

# rust target → rubygems platform (keep in sync with
# omnizip-rs .github/workflows/release-binary.yml)
PLATFORM_GEM_TARGETS = {
  "x86_64-unknown-linux-gnu" => "x86_64-linux",
  "aarch64-unknown-linux-gnu" => "aarch64-linux",
  "arm-unknown-linux-gnueabihf" => "arm-linux",
  "x86_64-unknown-linux-musl" => "x86_64-linux-musl",
  "aarch64-unknown-linux-musl" => "aarch64-linux-musl",
  "arm-unknown-linux-musleabihf" => "arm-linux-musl",
  "aarch64-apple-darwin" => "arm64-darwin",
  "x86_64-apple-darwin" => "x86_64-darwin",
  "x86_64-pc-windows-msvc" => "x64-mingw-ucrt",
  "aarch64-pc-windows-msvc" => "aarch64-mingw-ucrt",
  "x86_64-pc-windows-gnu" => "x64-mingw32",
}.freeze

namespace :platform_gems do
  desc "Build one platform gem: TARGET=<rust target> DYLIB=<cdylib path>"
  task :one do
    target = ENV.fetch("TARGET") { abort "TARGET=<rust target> required" }
    dylib = ENV.fetch("DYLIB") { abort "DYLIB=<cdylib path> required" }
    platform = PLATFORM_GEM_TARGETS[target] or abort "unknown target #{target} (see lib/tasks/platform_gems.rake)"
    out = build_platform_gem(platform, dylib)
    puts "built: #{out}"
  end

  desc "Build platform gems for every tarball in DIR=libomnizip_ffi-<target>.tar.gz"
  task :build do
    dir = ENV.fetch("DIR") { abort "DIR=<artifacts dir> required" }
    # Snapshot the pristine file list once. Gem::Specification.load
    # caches by path and returns the SAME object on every call, so a
    # per-call load + files += would leak the previous platform's
    # cdylib into the next gem.
    gem_root = File.expand_path("../..", __dir__)
    base_spec = Gem::Specification.load(File.join(gem_root, "omnizip.gemspec"))
    abort "omnizip.gemspec failed to load" unless base_spec
    base_files = base_spec.files.select { |rel| File.file?(File.join(gem_root, rel)) }.freeze

    Dir.glob(File.join(dir, "libomnizip_ffi-*.tar.gz")).each do |tarball|
      target = File.basename(tarball, ".tar.gz").delete_prefix("libomnizip_ffi-")
      platform = PLATFORM_GEM_TARGETS[target] or abort "no rubygems platform mapping for #{target}"
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        binary = extract_binary(tarball, tmp)
        out = build_platform_gem(platform, binary, base_files)
        puts "built: #{out} (#{File.size(out)} bytes)"
      end
    end
  end

  def extract_binary(tarball, tmp)
    system("tar", "-xzf", tarball, "-C", tmp) or abort "tar failed for #{tarball}"
    Dir.glob(File.join(tmp, "*")).first or abort "empty tarball #{tarball}"
  end

  # Stage the tracked gem files plus the vendored cdylib, flip the
  # gemspec platform, and build. `base_files` is the pristine
  # gemspec file list (frozen); we ASSIGN a fresh list every call
  # rather than mutating via +=, because Gem::Specification.load
  # hands back a cached object.
  def build_platform_gem(platform, dylib, base_files = nil)
    require "fileutils"
    require "rubygems/package"
    require "tmpdir"

    gem_root = File.expand_path("../..", __dir__)
    spec = Gem::Specification.load(File.join(gem_root, "omnizip.gemspec"))
    abort "omnizip.gemspec failed to load" unless spec
    base_files ||= spec.files.select { |rel| File.file?(File.join(gem_root, rel)) }

    Dir.mktmpdir do |tmp|
      stage = File.join(tmp, "stage")
      base_files.each do |rel|
        dst = File.join(stage, rel)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(File.join(gem_root, rel), dst)
      end

      vendored = "vendor/libomnizip_ffi#{File.extname(dylib)}"
      FileUtils.mkdir_p(File.join(stage, "vendor"))
      FileUtils.cp(dylib, File.join(stage, vendored))
      abort "staged cdylib missing: #{vendored}" unless File.file?(File.join(stage, vendored))

      spec.platform = Gem::Platform.new(platform)
      spec.files = base_files + [vendored]
      spec.test_files = []

      Dir.chdir(stage) do
        Gem::Package.build(spec)
      end
      built = Dir.glob(File.join(stage, "omnizip-*.gem")).first or
        abort "gem build produced nothing for #{platform}"
      FileUtils.mkdir_p(File.join(gem_root, "pkg"))
      FileUtils.mv(built, File.join(gem_root, "pkg", File.basename(built)))
      File.join(gem_root, "pkg", File.basename(built))
    end
  end
end
