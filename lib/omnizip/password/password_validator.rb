# frozen_string_literal: true

module Omnizip
  module Password
    # Validates password strength and requirements
    class PasswordValidator
      attr_reader :min_length, :require_uppercase, :require_lowercase,
                  :require_numbers, :require_special

      # Initialize password validator
      # @param min_length [Integer] Minimum password length
      # @param require_uppercase [Boolean] Require uppercase letters
      # @param require_lowercase [Boolean] Require lowercase letters
      # @param require_numbers [Boolean] Require numbers
      # @param require_special [Boolean] Require special characters
      def initialize(
        min_length: 8,
        require_uppercase: false,
        require_lowercase: false,
        require_numbers: false,
        require_special: false
      )
        @min_length = min_length
        @require_uppercase = require_uppercase
        @require_lowercase = require_lowercase
        @require_numbers = require_numbers
        @require_special = require_special
      end

      # Validate password
      # @param password [String] Password to validate
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If password is invalid
      def validate(password)
        raise ArgumentError, "Password cannot be nil" if password.nil?
        raise ArgumentError, "Password cannot be empty" if password.empty?

        check_length(password)
        check_uppercase(password) if require_uppercase
        check_lowercase(password) if require_lowercase
        check_numbers(password) if require_numbers
        check_special(password) if require_special

        true
      end

      # Check if password is valid (without raising)
      # @param password [String] Password to check
      # @return [Boolean] True if valid
      def valid?(password)
        validate(password)
        true
      rescue ArgumentError
        false
      end

      # Get password strength score (0-100)
      # @param password [String] Password to score
      # @return [Integer] Strength score
      def strength(password)
        return 0 if password.nil? || password.empty?

        score = 0

        # Length score (up to 40 points)
        score += [password.length * 4, 40].min

        # Character variety (up to 60 points)
        score += 15 if /[a-z]/.match?(password)
        score += 15 if /[A-Z]/.match?(password)
        score += 15 if /[0-9]/.match?(password)
        score += 15 if /[^a-zA-Z0-9]/.match?(password)

        [score, 100].min
      end

      # Get password strength label
      # @param password [String] Password to evaluate
      # @return [Symbol] Strength label (:weak, :fair, :good, :strong)
      def strength_label(password)
        score = strength(password)

        case score
        when 0...30
          :weak
        when 30...50
          :fair
        when 50...75
          :good
        else
          :strong
        end
      end

      private

      def check_length(password)
        return if password.length >= min_length

        raise ArgumentError,
              "Password too short (minimum: #{min_length} characters)"
      end

      def check_uppercase(password)
        return if /[A-Z]/.match?(password)

        raise ArgumentError, "Password must contain uppercase letters"
      end

      def check_lowercase(password)
        return if /[a-z]/.match?(password)

        raise ArgumentError, "Password must contain lowercase letters"
      end

      def check_numbers(password)
        return if /[0-9]/.match?(password)

        raise ArgumentError, "Password must contain numbers"
      end

      def check_special(password)
        return if /[^a-zA-Z0-9]/.match?(password)

        raise ArgumentError, "Password must contain special characters"
      end
    end
  end
end
