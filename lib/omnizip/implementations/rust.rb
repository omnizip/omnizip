# frozen_string_literal: true

module Omnizip
  module Implementations
    # Rust-accelerated codec backend (TODO.ref-parity/62).
    #
    # Loads the omnizip-ffi cdylib through stdlib Fiddle — no
    # compiled Ruby extension, no rake-compiler. When the library
    # is unavailable the gem transparently stays on the pure-Ruby
    # path; nothing about the fallback is an error.
    #
    # Library resolution order:
    #   1. ENV['OMNIZIP_FFI_DYLIB'] (explicit path)
    #   2. ../target/release/ inside a sibling omnizip-rs checkout
    #
    # Tier policy (see Omnizip::Backends): Rust is the authority —
    # validated against the reference C/C++ implementations and
    # determinism-contracted — so `auto` routes BOTH directions
    # through Rust whenever the library loads, with Ruby-core
    # fallback on any Rust error.
    module Rust
      autoload :Library, "omnizip/implementations/rust/library"
    end
  end
end
