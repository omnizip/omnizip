# frozen_string_literal: true

# Installed-gem smoke gate for platform gems (runs after
# `gem install pkg/omnizip-*-<platform>.gem` on a matching runner).
#
# Asserts the four distribution invariants:
#   1. the vendored cdylib loads with ZERO compilation (no cargo, no
#      sibling checkout, no ENV pointing anywhere);
#   2. the codec tier round-trips;
#   3. the archive tier (ArchHandle) lists and reads entries;
#   4. the same installed gem still works pure-Ruby with the tier
#      force-disabled (OMNIZIP_NO_RUST=1) — JRuby-grade safety.
abort "FAIL: omnizip did not load" unless require "omnizip"

require "tempfile"
require "rbconfig"

lib = Omnizip::Implementations::Rust::Library
instance = lib.instance
abort "FAIL: cdylib did not load from the installed gem" if instance.nil?

version = lib.dylib_version
abort "FAIL: ozip_version symbol missing — dylib predates the platform-gem contract" if version.nil?
layer = lib.binding_layer
abort "FAIL: unknown binding layer" if layer.nil?
puts "omnizip #{Omnizip::VERSION} + rust cdylib #{version} (#{RUBY_PLATFORM}, #{layer} layer)"

# JRuby/TruffleRuby have no Fiddle — the ffi layer is their ONLY path
# to the tier. When the smoke runs on such an engine, the layer check
# above is the assertion; on MRI both layers must work.
if RUBY_PLATFORM.include?("java") && layer != "ffi"
  abort "FAIL: expected the ffi layer on a JVM engine, got #{layer}"
end

data = "omnizip platform-gem smoke " * 2000
enc = instance.compress("zlib", data, 6)
abort "FAIL: zlib tier compress" if enc.nil? || enc.bytesize.zero?
abort "FAIL: zlib tier round-trip" unless instance.decompress("zlib", enc, data.bytesize) == data

zip_path = File.join(Dir.tmpdir, "omnizip-smoke-#{Process.pid}.zip")
Omnizip::Zip::File.open(zip_path, create: true) do |z|
  z.send(:add_data, "smoke.txt", data)
end
names = Omnizip::Backends.archive_entry_names(zip_path)
abort "FAIL: archive tier names: #{names.inspect}" unless names == ["smoke.txt"]
entry = Omnizip::Backends.archive_read_entry(zip_path, "smoke.txt")
abort "FAIL: archive tier read_entry" unless entry == data
File.delete(zip_path)

pure = system(
  { "OMNIZIP_NO_RUST" => "1" },
  RbConfig.ruby, "-e",
  'require "omnizip"; ' \
  'data = "pure ruby fallback " * 1000; ' \
  "compressed = Omnizip::Algorithms::Deflate.compress(data); " \
  'abort "FAIL: pure-ruby round-trip diverged" unless Omnizip::Algorithms::Deflate.decompress(compressed) == data; ' \
  'puts "pure-ruby path OK"'
)
abort "FAIL: pure-ruby path with OMNIZIP_NO_RUST=1" unless pure

puts "SMOKE OK (#{layer} layer)"
