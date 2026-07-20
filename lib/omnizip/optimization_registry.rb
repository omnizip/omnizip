# frozen_string_literal: true

module Omnizip
  class OptimizationRegistry < Omnizip::Registry
    class << self
      def not_found_error_class
        Omnizip::OptimizationNotFoundError
      end

      def label
        "Optimization strategy"
      end

      def apply(name, target, **options)
        get(name).new(**options).optimize(target)
      end

      def metadata(name)
        get(name).metadata
      end
    end

    class Strategy
      attr_reader :options

      def initialize(**options)
        @options = options
      end

      def optimize(_target)
        raise NotImplementedError,
              "#{self.class} must implement #optimize"
      end

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
