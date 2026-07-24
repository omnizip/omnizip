# frozen_string_literal: true

module Omnizip
  module Converter
    # Registry for conversion strategies
    class ConversionRegistry
      @strategies = []

      class << self
        # Register a conversion strategy
        # @param strategy_class [Class] Strategy class
        def register(strategy_class)
          @strategies << strategy_class unless @strategies.include?(strategy_class)
        end

        # Find strategy for source and target formats
        # @param source [String] Source file path
        # @param target [String] Target file path
        # @return [Class, nil] Strategy class or nil
        def find_strategy(source, target)
          @strategies.find { |strategy| strategy.can_convert?(source, target) }
        end

        # Get all registered strategies
        # @return [Array<Class>] List of strategy classes
        def strategies
          @strategies
        end

        # Check if conversion is supported
        # @param source [String] Source file path
        # @param target [String] Target file path
        # @return [Boolean] True if supported
        def supported?(source, target)
          !find_strategy(source, target).nil?
        end

        # Reset registry (for testing)
        def reset
          @strategies = []
        end
      end
    end

    # Register built-in strategies
    ConversionRegistry.register(ZipToSevenZipStrategy)
    ConversionRegistry.register(SevenZipToZipStrategy)
  end
end
