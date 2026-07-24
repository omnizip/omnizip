# frozen_string_literal: true


require "omnizip"
module Omnizip
  class Cli
    # Shared helpers used by the Thor command groups defined in
    # lib/omnizip/cli.rb (ProfileCommands, ArchiveCommands, Cli).
    module Shared
      # Print a formatted error message and exit nonzero.
      #
      # @param error [StandardError] the error to display
      def handle_error(error)
        warn Omnizip::CliOutputFormatter.format_error(error)
        exit 1
      end

      # Format a byte count with a binary-unit suffix.
      #
      # @param bytes [Integer] the byte count
      # @return [String] human-readable size (e.g. "1.5 MB")
      def format_bytes(bytes)
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB TB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.size - 1].min

        "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
      end
    end
  end
end
