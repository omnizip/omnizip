# frozen_string_literal: true

# One command to build the Rust-accelerated backend's cdylib into
# the gem's vendor dir (TODO.ref-parity/62 — the distribution
# story). Requires git + a Rust toolchain; the gem stays fully
# functional (pure Ruby) without ever running this.
#
#   bundle exec rake rust:build
#   bundle exec rake rust:build REPO=/path/to/omnizip-rs
desc "Build the omnizip-ffi cdylib into vendor/ for the Rust tier"
task "rust:build" do
  repo = ENV.fetch("REPO", nil)
  gem_root = File.expand_path("../..", __dir__)
  build = File.join(gem_root, "build", "rust")

  require "fileutils"
  FileUtils.mkdir_p(build)
  src = if repo
          File.expand_path(repo)
        else
          target = File.join(build, "omnizip-rs")
          if File.directory?(File.join(target, ".git"))
            system("git", "-C", target, "fetch", "--quiet", "origin") or abort "git fetch failed in #{target}"
            system("git", "-C", target, "reset", "--quiet", "--hard", "origin/main") or abort "git reset failed"
          else
            system("git", "clone", "--quiet", "--depth", "1",
                   "https://github.com/omnizip/omnizip-rs.git", target) or abort "clone failed"
          end
          target
        end

  abort "#{src} has no omnizip-ffi crate" unless File.directory?(File.join(src, "omnizip-ffi"))

  system("cargo", "build", "--release", "-p", "omnizip-ffi", chdir: src) or abort "cargo build failed"

  vendor = File.join(gem_root, "vendor")
  FileUtils.mkdir_p(vendor)
  %w[dylib so dll].each do |ext|
    candidate = File.join(src, "target", "release", "libomnizip_ffi.#{ext}")
    next unless File.file?(candidate)

    FileUtils.cp(candidate, vendor)
    puts "vendored: #{File.join(vendor, "libomnizip_ffi.#{ext}")}"
    puts "tier: OMNIZIP_BACKEND=auto now uses the Rust decoders"
    exit 0
  end
  abort "cdylib not found under #{src}/target/release"
end
