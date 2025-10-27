# frozen_string_literal: true

require_relative "constants"
require_relative "../../algorithm_registry"
require_relative "../../filter_registry"
require_relative "../../filter_pipeline"

module Omnizip
  module Formats
    module SevenZip
      # Builds coder chains from .7z folder specifications
      # Maps method IDs to algorithms and filters, reconstructing the
      # decompression pipeline
      class CoderChain
        include Constants

        # Build coder chain from folder specification
        #
        # @param folder [Models::Folder] Folder specification
        # @return [Hash] Coder chain configuration
        # @raise [RuntimeError] if unsupported method encountered
        def self.build_from_folder(folder)
          return nil if folder.coders.empty?

          # For now, support single coder or coder+filter combinations
          main_coder = folder.coders.last
          algorithm = algorithm_for_method(main_coder.method_id)

          # Check for filters
          filters = []
          if folder.coders.size > 1
            folder.coders[0..-2].each do |coder|
              filter = filter_for_method(coder.method_id)
              filters << filter if filter
            end
          end

          {
            algorithm: algorithm,
            filters: filters,
            properties: main_coder.properties,
            unpack_size: folder.unpack_sizes.last
          }
        end

        # Map method ID to algorithm
        #
        # @param method_id [Integer] Method ID from .7z file
        # @return [Symbol] Algorithm identifier
        # @raise [RuntimeError] if method not supported
        def self.algorithm_for_method(method_id)
          case method_id
          when MethodId::COPY
            nil # No decompression needed
          when MethodId::LZMA
            :lzma
          when MethodId::LZMA2
            :lzma2
          when MethodId::PPMD
            :ppmd7
          when MethodId::BZIP2
            :bzip2
          when MethodId::DEFLATE
            raise "Deflate not yet implemented"
          when MethodId::DEFLATE64
            raise "Deflate64 not yet implemented"
          else
            raise "Unsupported compression method: " \
                  "0x#{method_id.to_s(16)}"
          end
        end

        # Map method ID to filter
        #
        # @param method_id [Integer] Method ID from .7z file
        # @return [Symbol, nil] Filter identifier or nil
        def self.filter_for_method(method_id)
          case method_id
          when FilterId::BCJ_X86
            :bcj_x86
          when FilterId::DELTA
            :delta
          when FilterId::BCJ_PPC, FilterId::BCJ_IA64,
               FilterId::BCJ_ARM, FilterId::BCJ_ARMT, FilterId::BCJ_SPARC
            raise "BCJ filter variant not yet implemented: " \
                  "0x#{method_id.to_s(16)}"
          end
        end

        # Create decompressor for coder chain
        #
        # @param chain_config [Hash] Chain configuration
        # @param input_io [IO] Input stream
        # @return [Object] Decompressor instance
        def self.create_decompressor(chain_config, input_io)
          return nil unless chain_config
          return input_io unless chain_config[:algorithm]

          # Get algorithm
          algo_class = AlgorithmRegistry.get(chain_config[:algorithm])
          unless algo_class
            raise "Algorithm not found: #{chain_config[:algorithm]}"
          end

          # Create algorithm instance
          decompressor = algo_class.new
          # Pass properties if algorithm supports them
          # Some algorithms (LZMA2) need properties
          if chain_config[:properties] && !chain_config[:properties].empty? && decompressor.respond_to?(:properties=)
            decompressor.properties = chain_config[:properties]
          end

          # Apply filters if present
          if chain_config[:filters] && !chain_config[:filters].empty?
            # Build filter pipeline
            pipeline = FilterPipeline.new
            chain_config[:filters].each do |filter_sym|
              filter_class = FilterRegistry.get(filter_sym)
              raise "Filter not found: #{filter_sym}" unless filter_class

              pipeline.add_filter(filter_class.new)
            end

            # Return composite: input -> algorithm -> filters
            {
              decompressor: decompressor,
              pipeline: pipeline,
              input: input_io
            }
          else
            # Just algorithm
            {
              decompressor: decompressor,
              pipeline: nil,
              input: input_io
            }
          end
        end
      end
    end
  end
end
