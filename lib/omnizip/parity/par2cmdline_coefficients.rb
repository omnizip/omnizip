# frozen_string_literal: true

# Par2cmdline coefficient lookup table
#
# Discovered by reverse-engineering par2cmdline recovery blocks.
# Par2cmdline uses the SAME coefficient for ALL data blocks for a given exponent.
# This is different from standard Vandermonde matrix approach.
#
# Formula: coefficient[exponent, data_index] = PAR2CMDLINE_COEFFICIENTS[exponent]
#          (same coefficient for all data_index values)

module Omnizip
  module Parity
    # Par2cmdline-compatible coefficient table
    PAR2CMDLINE_COEFFICIENTS = {
      0 => 0x27c6,
      1 => 0x8eb6,
      2 => 0x1a9f,
      3 => 0x2743,
      4 => 0x24f6,
      5 => 0x60d7,
      6 => 0x2027,
      7 => 0x1cf0,
      8 => 0xd37a,
      9 => 0xa961,
      10 => 0xc6c7,
      11 => 0x653e,
      12 => 0x9c99,
      13 => 0x2e1b,
      14 => 0x8625,
      15 => 0xd81e,
      16 => 0x1fb5,
      17 => 0x2cdd,
      18 => 0x06ce,
      19 => 0x41d5,
      20 => 0xd297,
      21 => 0xeae1,
      22 => 0x9012,
      23 => 0xdc31,
      24 => 0xa33d,
      25 => 0x2480,
      26 => 0x3e2e,
      27 => 0x5dee,
      28 => 0x8f63,
      29 => 0x90c5,
      30 => 0xac21,
      31 => 0x9bf4,
      32 => 0x8b15,
      33 => 0xc489,
      34 => 0x004c,
      35 => 0x6a45,
      36 => 0x56f9,
      37 => 0x6956,
      38 => 0x2548,
      39 => 0x0334,
      40 => 0x3213,
      41 => 0x7c7f,
      42 => 0x1d3c,
      43 => 0x9c1e,
      44 => 0x835c,
      45 => 0x7f30,
      46 => 0x070e,
      47 => 0x5f7d,
      48 => 0x5f97,
      49 => 0xfa32,
      50 => 0x08fd,
      51 => 0x9d43,
      52 => 0x9ec1,
      53 => 0x4643,
      54 => 0x9222,
      55 => 0x1f9c,
      56 => 0xd271,
      57 => 0xbd9f,
      58 => 0xfef3,
      59 => 0x9b83,
    }.freeze
  end
end
