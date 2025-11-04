# frozen_string_literal: true

module Omnizip
  module Password
    # Registry for encryption strategies
    class EncryptionRegistry
      @strategies = {}

      class << self
        # Register an encryption strategy
        # @param name [Symbol] Strategy name
        # @param strategy_class [Class] Strategy class
        def register(name, strategy_class)
          @strategies[name] = strategy_class
        end

        # Get a strategy by name
        # @param name [Symbol] Strategy name
        # @return [Class] Strategy class
        # @raise [ArgumentError] If strategy not found
        def get(name)
          strategy = @strategies[name]
          return strategy if strategy

          raise ArgumentError, "Unknown encryption strategy: #{name}. " \
                              "Available: #{@strategies.keys.join(', ')}"
        end

        # Check if strategy is registered
        # @param name [Symbol] Strategy name
        # @return [Boolean] True if registered
        def registered?(name)
          @strategies.key?(name)
        end

        # Get all registered strategy names
        # @return [Array<Symbol>] Strategy names
        def strategies
          @strategies.keys
        end

        # Create a strategy instance
        # @param name [Symbol] Strategy name
        # @param password [String] Password
        # @param options [Hash] Strategy options
        # @return [EncryptionStrategy] Strategy instance
        def create(name, password, **options)
          strategy_class = get(name)
          strategy_class.new(password, **options)
        end

        # Reset registry (for testing)
        def reset
          @strategies = {}
        end
      end
    end

    # Register built-in strategies
    EncryptionRegistry.register(:traditional, ZipCryptoStrategy)
    EncryptionRegistry.register(:zip_crypto, ZipCryptoStrategy)
    EncryptionRegistry.register(:winzip_aes, WinzipAesStrategy)
    EncryptionRegistry.register(:aes256, WinzipAesStrategy)
  end
end