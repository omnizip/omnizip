# frozen_string_literal: true

module Omnizip
  # I/O utilities module
  #
  # Provides buffered I/O operations and stream management
  # for efficient handling of large files.
  module IO
    autoload :BufferedInput, "omnizip/io/buffered_input"
    autoload :BufferedOutput, "omnizip/io/buffered_output"
    autoload :StreamManager, "omnizip/io/stream_manager"
  end
end
