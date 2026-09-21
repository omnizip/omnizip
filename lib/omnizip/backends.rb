# frozen_string_literal: true

module Omnizip
  # Byte-level codec backend resolution — THE tier switch
  # (TODO.ref-parity/62). Both paths share the algorithm classes'
  # IO plumbing; only the byte core swaps.
  #
  # Policy:
  #   OMNIZIP_BACKEND=ruby   force pure Ruby everywhere
  #   OMNIZIP_BACKEND=rust   require the Rust library (raises when absent)
  #   OMNIZIP_BACKEND=auto   (default) Rust for directions marked
  #                          safe, Ruby otherwise, whenever the
  #                          cdylib is loadable
  #
  # Safety marks (owner guidance 2026-09-19: some Ruby cores are
  # LESS accurate than the Rust ports — be careful which tier is
  # trusted for what):
  #   - decompress -> :rust by default. Decode is output-invariant
  #     AND the Rust decoders carry fixes the Ruby cores lack;
  #     disagreements are treated as Ruby-side accuracy findings
  #     (see the cross-tier differential spec), not coin flips.
  #   - compress -> :ruby by default. Byte-stability for content
  #     addressing (DropId dedup assumes identical frames); the
  #     Rust encoders produce DIFFERENT valid streams (probed:
  #     bzip2 L6, Ruby 906 B vs Rust 874 B). OMNIZIP_BACKEND=rust
  #     opts into Rust encode where correctness-of-ratio is wanted
  #     over frame stability.
  module Backends
    # Codecs whose Rust encoder is BYTE-IDENTICAL to the pure-Ruby
    # 2026-09-20 policy flip (owner directive): RUST IS THE AUTHORITY
    # — its encoders/decoders are the ports validated against the
    # reference C/C++ implementations (bzip2, xz/liblzma, zstd,
    # libdeflate), and they are determinism-contracted (same input +
    # level => same bytes on every machine). :auto therefore routes
    # BOTH directions through Rust whenever the cdylib loads; encode
    # falls back to the Ruby core on any Rust error, so :auto is
    # never worse than pure Ruby. The pure-Ruby cores remain the
    # portable fallback and the OMNIZIP_BACKEND=ruby escape hatch.
    RUST_AUTHORITATIVE = true

    # usize::MAX — the FFI's "caller does not know the plaintext
    # size" sentinel (streaming decode contract).
    UNKNOWN_LENGTH = 0xFFFF_FFFF_FFFF_FFFF

    class << self
      def for(codec, _direction)
        mode = ENV.fetch("OMNIZIP_BACKEND", "auto")

        return backend_rust if mode == "rust"
        return backend_ruby if mode == "ruby"

        return backend_ruby unless Implementations::Rust::Library.available?
        return backend_ruby unless Implementations::Rust::Library.supports?(codec)

        backend_rust
      end

      # Compress through the tier-selected backend. The block is
      # the pure-Ruby core — evaluated ONLY on the Ruby path, so
      # the accelerated path never pays for it. A Rust encode error
      # falls back to the Ruby core (auto is never worse than pure
      # Ruby); only the forced `rust` mode propagates.
      def compress(codec, data, level, &ruby_core)
        backend = Backends.for(codec, :encode)
        return yield if backend == RubyBackend

        begin
          backend.compress(codec, data, level)
        rescue Implementations::Rust::Error => e
          raise if ENV.fetch("OMNIZIP_BACKEND", "auto") == "rust"

          warn "omnizip: rust #{codec} encode failed (#{e.message}); using ruby" if ENV["OMNIZIP_BACKEND_DEBUG"]
          yield
        end
      end

      # Decompress through the tier-selected backend (output-
      # invariant: :auto prefers Rust whenever loadable). A Rust
      # failure falls back to the Ruby core — the Ruby readers are
      # the tolerant superset (legacy container variants, malformed
      # inputs they historically accept), so :auto must never be
      # WORSE than pure Ruby. Only the forced `rust` mode propagates.
      def decompress(codec, data, expected_len, &ruby_core)
        backend = Backends.for(codec, :decode)
        return yield if backend == RubyBackend

        begin
          backend.decompress(codec, data, expected_len)
        rescue Implementations::Rust::Error => e
          raise if ENV.fetch("OMNIZIP_BACKEND", "auto") == "rust"

          warn "omnizip: rust #{codec} decode failed (#{e.message}); using ruby" if ENV["OMNIZIP_BACKEND_DEBUG"]
          yield
        end
      end

      # Whole-archive tier helpers: nil means "Rust unavailable or
      # entry not found — caller falls back to the Ruby reader".
      # Encrypted formats (rar, 7z) pass password:.
      def archive_entry_names(path, password: nil)
        Omnizip::Implementations::Rust::Archive.open(File.binread(path), password: password) do |a|
          return a.entry_names
        end
      rescue Omnizip::Implementations::Rust::Archive::LibraryMissing, Omnizip::Implementations::Rust::Error, StandardError
        nil
      end

      # rubocop:disable-next Lint/ReturnInVoidContext
      def archive_read_entry(path, entry_name, password: nil)
        Omnizip::Implementations::Rust::Archive.open(File.binread(path), password: password) do |a|
          idx = a.entry_names.index(entry_name)
          return nil if idx.nil?

          return a.read_entry(idx)
        end
      rescue Omnizip::Implementations::Rust::Archive::LibraryMissing, Omnizip::Implementations::Rust::Error, StandardError
        nil
      end

      private

      def backend_rust
        RustBackend
      end

      def backend_ruby
        RubyBackend
      end
    end

    # The pure-Ruby path: a no-op backend — callers fall back to
    # their own in-tree cores, which ARE the reference. Kept as an
    # object for symmetry with the Rust side.
    module RubyBackend
      module_function

      # :nocov:
      def compress(codec, _data, _level)
        raise Error, "#{codec}: ruby core not wired through Backends (call it directly)"
      end

      def decompress(codec, _data, _expected_len)
        raise Error, "#{codec}: ruby core not wired through Backends (call it directly)"
      end
      # :nocov:
    end

    # The Rust-accelerated path over the Fiddle handle.
    module RustBackend
      module_function

      def compress(codec, data, level)
        Implementations::Rust::Library.instance.compress(codec, data, level)
      end

      def decompress(codec, data, expected_len)
        Implementations::Rust::Library.instance.decompress(codec, data, expected_len)
      end
    end

    class Error < StandardError; end
  end
end
