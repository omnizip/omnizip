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

          # Find the compression method (not a filter) among coders
          # Filters like BCJ, BCJ2 have specific method IDs
          main_coder = find_compression_coder(folder.coders)
          raise "No compression method found in folder" unless main_coder

          algorithm = algorithm_for_method(main_coder.method_id)

          # Check for filters (all coders except the compression method)
          filters = []
          folder.coders.each do |coder|
            next if coder == main_coder

            filter = filter_for_method(coder.method_id)
            filters << filter if filter
          end

          {
            algorithm: algorithm,
            filters: filters,
            properties: main_coder.properties,
            unpack_size: folder.unpack_sizes.last,
          }
        end

        # Find the compression coder among all coders
        #
        # @param coders [Array<Models::CoderInfo>] All coders in the folder
        # @return [Models::CoderInfo, nil] The compression coder or nil
        def self.find_compression_coder(coders)
          # Try to find a known compression method
          coders.each do |coder|
            case coder.method_id
            when MethodId::LZMA, MethodId::LZMA2, MethodId::BZIP2,
                 MethodId::DEFLATE, MethodId::DEFLATE64, MethodId::PPMD,
                 MethodId::COPY
              return coder
            end
          end

          # Fall back to last coder if no known compression method found
          coders.last
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
            :deflate
          when MethodId::DEFLATE64
            :deflate64
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
          when FilterId::BCJ_PPC
            :bcj_ppc
          when FilterId::BCJ_IA64
            :bcj_ia64
          when FilterId::BCJ_ARM
            :bcj_arm
          when FilterId::BCJ_ARMT
            :bcj_armt
          when FilterId::BCJ_SPARC
            :bcj_sparc
          when FilterId::ARM64
            :bcj_arm64
          when FilterId::DELTA
            :delta
          when FilterId::BCJ2
            :bcj2
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
              input: input_io,
            }
          else
            # Just algorithm
            {
              decompressor: decompressor,
              pipeline: nil,
              input: input_io,
            }
          end
        end
      end
    end
  end
end
