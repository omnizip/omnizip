# frozen_string_literal: true

module Omnizip
  # Registry for performance optimization strategies using the Registry pattern
  class OptimizationRegistry
    class << self
      # Register an optimization strategy
      def register(name, strategy_class)
        strategies[name] = strategy_class
      end

      # Get an optimization strategy by name
      def get(name)
        strategies[name] || raise(
          Omnizip::OptimizationNotFound,
          "Optimization strategy not found: #{name}",
        )
      end

      # Check if an optimization strategy is registered
      def registered?(name)
        strategies.key?(name)
      end

      # List all registered optimization strategies
      def all
        strategies.keys
      end

      # Get all optimization strategies as a hash
      def strategies
        @strategies ||= {}
      end

      # Clear all registered strategies (useful for testing)
      def clear!
        @strategies = {}
      end

      # Apply an optimization strategy to a target
      def apply(name, target, **options)
        strategy_class = get(name)
        strategy = strategy_class.new(**options)
        strategy.optimize(target)
      end

      # Get optimization metadata
      def metadata(name)
        strategy_class = get(name)
        return {} unless strategy_class.respond_to?(:metadata)

        strategy_class.metadata
      end
    end

    # Base class for optimization strategies
    class Strategy
      attr_reader :options

      def initialize(**options)
        @options = options
      end

      # Override in subclasses to implement optimization logic
      def optimize(target)
        raise NotImplementedError,
              "#{self.class} must implement #optimize"
      end

      # Override in subclasses to provide strategy metadata
      def self.metadata
        {
          name: name,
          description: "No description provided",
          category: :general,
          impact: :unknown,
        }
      end
    end
  end
end
