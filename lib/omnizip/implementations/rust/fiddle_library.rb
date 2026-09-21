# frozen_string_literal: true

module Omnizip
  module Implementations
    module Rust
      # The Fiddle binding of the cdylib's C ABI — the MRI fast path
      # (stdlib, zero gems). One public surface shared with
      # FfiLibrary: codec methods, whole-archive methods, error and
      # version accessors — the binding Library's facade and the
      # Archive class dispatch through.
      class FiddleLibrary
        attr_reader :handle

        # The shared function table (Fiddle::TYPE_* constants resolve
        # only after a successful require — same reason Library keeps
        # this out of the class body).
        FUNCTION_TABLE = lambda {
          {
            last_error: ["ozip_last_error", [], Fiddle::TYPE_VOIDP],
            free: ["ozip_free", %i[voidp size_t], Fiddle::TYPE_VOID],
            compress: [
              "ozip_compress",
              %i[voidp voidp size_t int voidp],
              Fiddle::TYPE_VOIDP,
            ],
            decompress: [
              "ozip_decompress",
              %i[voidp voidp size_t size_t voidp],
              Fiddle::TYPE_VOIDP,
            ],
          }
        }

        FIDDLE_ARG_TYPES = {
          pointer: ->(v) { v.nil? ? nil : Fiddle::Pointer[v] },
        }.freeze
        FIDDLE_RET_TYPES = {
          pointer: Fiddle::TYPE_VOIDP,
          void: Fiddle::TYPE_VOID,
          size_t: Fiddle::TYPE_SIZE_T,
          uint64: Fiddle::TYPE_VOIDP,
        }.freeze

        def initialize(path)
          @handle = Fiddle.dlopen(path.to_s)
          @funcs = FUNCTION_TABLE.call.each_with_object({}) do |(key, (name, args, ret)), h|
            h[key] = Fiddle::Function.new(@handle[name], args, ret)
          end
        end

        def compress(codec, data, level)
          out_len = [0].pack("Q")
          ptr = @funcs[:compress].call(codec, data, data.bytesize, level, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.unpack1("Q"))
        end

        def decompress(codec, data, expected_len)
          out_len = [0].pack("Q")
          ptr = @funcs[:decompress].call(codec, data, data.bytesize, expected_len, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.unpack1("Q"))
        end

        def last_error
          ptr = @funcs[:last_error].call
          ptr.null? ? "unknown error" : ptr.to_s
        end

        # Copy out + free one returned buffer: the buffer belongs to
        # the Rust allocator and must never outlive ozip_free.
        def take(ptr, len)
          s = ptr.to_s(len)
          @funcs[:free].call(ptr, len)
          s
        end

        def take_buffer(ptr, len)
          take(ptr, len)
        end

        # The Rust release this cdylib was built from, or nil when the
        # symbol is absent (dylibs older than 0.21.109).
        def dylib_version
          func = Fiddle::Function.new(@handle["ozip_version"], [], Fiddle::TYPE_VOIDP)
          ptr = func.call
          ptr.null? ? nil : ptr.to_s
        rescue StandardError
          nil
        end

        # ---- whole-archive surface (ArchHandle) ----

        def arch_open(data, password)
          pw = password&.to_s
          pw_ptr = pw && !pw.empty? ? Fiddle::Pointer[pw] : nil
          ptr = Fiddle::Function.new(
            @handle["ozip_arch_open"],
            %i[voidp size_t voidp],
            Fiddle::TYPE_VOIDP,
          ).call(Fiddle::Pointer[data], data.bytesize, pw_ptr)
          raise Rust::Error, last_error if ptr.null?

          ptr
        end

        def arch_count(handle)
          fn = Fiddle::Function.new(@handle["ozip_arch_count"], [:voidp], Fiddle::TYPE_SIZE_T)
          fn.call(handle)
        end

        def arch_entry_name(handle, index)
          ptr = Fiddle::Function.new(
            @handle["ozip_arch_entry_name"], %i[voidp size_t], Fiddle::TYPE_VOIDP
          ).call(handle, index)
          ptr.null? ? nil : ptr.to_s
        end

        def arch_entry_size(handle, index)
          Fiddle::Function.new(
            @handle["ozip_arch_entry_size"], %i[voidp size_t], Fiddle::TYPE_VOIDP
          ).call(handle, index)
        end

        def arch_read_entry(handle, index)
          out_len = [0].pack("Q")
          ptr = Fiddle::Function.new(
            @handle["ozip_arch_read_entry"], %i[voidp size_t voidp], Fiddle::TYPE_VOIDP
          ).call(handle, index, out_len)
          raise Rust::Error, last_error if ptr.null?

          take(ptr, out_len.unpack1("Q"))
        end

        def arch_close(handle)
          Fiddle::Function.new(@handle["ozip_arch_close"], [:voidp], Fiddle::TYPE_VOID)
            .call(handle)
        end
      end
    end
  end
end
