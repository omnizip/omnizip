# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Model for parallel processing configuration
    #
    # Stores settings for parallel compression and extraction operations
    # including thread count, queue size, and load balancing strategy.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    #
    # @example Create parallel options
    #   options = Omnizip::Models::ParallelOptions.new
    #   options.threads = 8
    #   options.queue_size = 100
    #   options.strategy = :dynamic
    #
    # @example Use with parallel compression
    #   Omnizip::Parallel.compress_directory('files/', 'backup.zip', options)
    class ParallelOptions < Lutaml::Model::Serializable
      # @return [Integer] Number of worker threads (default: auto-detect)
      attribute :threads, :integer, default: -> { detect_cpu_count }

      # @return [Integer] Maximum size of job queue (default: 1000)
      attribute :queue_size, :integer, default: 1000

      # @return [Integer] Chunk size for chunked operations in bytes
      attribute :chunk_size, :integer, default: 64 * 1024 * 1024 # 64MB default

      # @return [Symbol] Load balancing strategy (:dynamic or :static)
      attribute :strategy, :symbol, default: :dynamic

      # @return [Boolean] Enable verbose progress output
      attribute :verbose, :boolean, default: false

      # @return [Integer] Batch size for work queue polling
      attribute :batch_size, :integer, default: 10

      key_value do
        map "threads", to: :threads, render_default: true, render_nil: true
        map "queue_size", to: :queue_size,
                          render_default: true, render_nil: true
        map "chunk_size", to: :chunk_size,
                          render_default: true, render_nil: true
        map "strategy", to: :strategy, render_default: true, render_nil: true
        map "verbose", to: :verbose, render_default: true, render_nil: true
        map "batch_size", to: :batch_size,
                          render_default: true, render_nil: true
      end

      # Validate options
      #
      # @raise [ArgumentError] if options are invalid
      # @return [Boolean] true if valid
      def validate!
        validate_positive(:threads)
        validate_positive(:queue_size)
        validate_positive(:chunk_size)
        validate_strategy
        validate_positive(:batch_size)

        true
      end

      # Apply a hash of attributes. Only keys declared as +attribute+s
      # above are applied; unknown keys are silently ignored.
      #
      # Keys must be Symbols. String keys are ignored, so +#to_hash+ output
      # cannot be fed back in directly — use +.from_hash+ for that.
      #
      # @param values [Hash{Symbol=>Object}] attributes to set
      # @return [self]
      def apply(values)
        self.class.attributes.each_key do |name|
          public_send("#{name}=", values[name]) if values.key?(name)
        end
        self
      end

      private

      # Raise unless +name+ holds a positive Integer. A nil or non-Integer
      # value fails with the same message as a zero or negative one, so
      # callers get +ArgumentError+ rather than +NoMethodError+.
      #
      # @param name [Symbol] attribute to check
      # @raise [ArgumentError] if the value is not a positive Integer
      # @return [void]
      def validate_positive(name)
        value = public_send(name)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be > 0"
      end

      # @raise [ArgumentError] unless +strategy+ is one of the known values
      # @return [void]
      def validate_strategy
        return if %i[dynamic static].include?(strategy)

        raise ArgumentError, "strategy must be :dynamic or :static"
      end

      # Detect number of available CPU cores
      #
      # @return [Integer] number of CPUs
      def detect_cpu_count
        require "etc"
        Etc.nprocessors
      rescue StandardError
        4 # fallback to 4 threads
      end
    end
  end
end
