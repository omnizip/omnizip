# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # Validates WinRAR license ownership
      #
      # This class ensures users confirm they own a valid WinRAR license
      # before allowing RAR archive creation, as RAR compression is proprietary.
      class LicenseValidator
        class << self
          # Check if user has confirmed license ownership
          #
          # @return [Boolean] true if license confirmed
          def license_confirmed?
            File.exist?(license_file_path) && valid_confirmation?
          end

          # Prompt user to confirm license and save confirmation
          #
          # @return [Boolean] true if user confirms
          def confirm_license!
            return true if license_confirmed?

            puts "\n#{'=' * 70}"
            puts "RAR License Confirmation Required"
            puts "=" * 70
            puts
            puts "RAR compression is proprietary and requires a WinRAR license."
            puts "By proceeding, you confirm that you own a valid WinRAR license."
            puts
            puts "License information:"
            puts "  - License can be purchased at: https://www.rarlab.com/"
            puts "  - Price: ~$29 for single user license"
            puts "  - License is perpetual (no subscription)"
            puts
            print "Do you own a valid WinRAR license? (yes/no): "

            response = $stdin.gets&.strip&.downcase

            if response == "yes"
              save_confirmation
              puts "\nLicense confirmed. You can now create RAR archives."
              true
            else
              puts "\nRAR creation requires a valid license."
              puts "Consider using 7z format as a free alternative."
              false
            end
          end

          # Reset license confirmation
          #
          # This removes the saved confirmation file
          def reset_confirmation
            FileUtils.rm_f(license_file_path)
          end

          private

          # Get path to license confirmation file
          #
          # @return [String] Path to confirmation file
          def license_file_path
            config_dir = File.join(Dir.home, ".omnizip")
            FileUtils.mkdir_p(config_dir)
            File.join(config_dir, "rar_license_confirmed")
          end

          # Save license confirmation
          def save_confirmation
            File.write(license_file_path, confirmation_data)
          end

          # Validate saved confirmation
          #
          # @return [Boolean] true if confirmation is valid
          def valid_confirmation?
            data = File.read(license_file_path)
            data.include?("CONFIRMED") && data.include?(Time.now.year.to_s)
          rescue StandardError
            false
          end

          # Generate confirmation data
          #
          # @return [String] Confirmation data
          def confirmation_data
            <<~CONF
              WinRAR License Confirmation
              Confirmed at: #{Time.now.iso8601}
              Year: #{Time.now.year}
              User: #{ENV['USER'] || ENV['USERNAME'] || 'unknown'}
              Hostname: #{begin
                Socket.gethostname
              rescue StandardError
                'unknown'
              end}
              Status: CONFIRMED

              This file indicates that the user has confirmed ownership
              of a valid WinRAR license for creating RAR archives.
            CONF
          end
        end
      end
    end
  end
end
