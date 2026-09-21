# frozen_string_literal: true

module Omnizip
  module Implementations
    module Rust
      # Whole-archive acceleration over the cdylib: open any supported
      # format (auto-detected), list entries, read entry bytes. This is
      # the archive-level tier surface — the Ruby core remains the
      # fallback (the cdylib unavailable ⇒ these raise LibraryMissing
      # and callers fall back). Binding-agnostic: dispatches through
      # whichever backend loaded (Fiddle on MRI, ffi on
      # JRuby/TruffleRuby).
      class Archive
        class LibraryMissing < StandardError; end

        def initialize(data, password: nil)
          lib = Library.instance
          raise LibraryMissing, "omnizip-ffi cdylib not loaded" unless lib

          @lib = lib
          @handle = @lib.arch_open(data, password)
        end

        def entry_count
          @lib.arch_count(@handle)
        end

        def entry_names
          (0...entry_count).map do |i|
            @lib.arch_entry_name(@handle, i)
          end
        end

        def entry_size(index)
          @lib.arch_entry_size(@handle, index)
        end

        # Read one entry's uncompressed bytes.
        #
        # @return [String] binary
        def read_entry(index)
          @lib.arch_read_entry(@handle, index)
        end

        def close
          return unless @handle

          @lib.arch_close(@handle)
          @handle = nil
        end

        def self.open(data, password: nil)
          archive = new(data, password: password)
          yield archive
        ensure
          archive&.close
        end
      end
    end
  end
end
