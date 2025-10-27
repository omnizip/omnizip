# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

module Omnizip
  module Algorithms
    class PPMd8 < PPMdBase
      # Strategy pattern for PPMd8 restoration methods
      #
      # PPMd8 supports multiple restoration methods that determine
      # how the model handles memory management and context updating
      # when memory is exhausted.
      class RestorationMethod
        include Constants

        attr_reader :method_type

        # Initialize restoration method
        #
        # @param method_type [Integer] The restoration method type
        def initialize(method_type = RESTORE_METHOD_RESTART)
          @method_type = method_type
        end

        # Execute restoration based on the selected method
        #
        # @param model [Model] The PPMd8 model to restore
        # @return [void]
        def restore(model)
          case @method_type
          when RESTORE_METHOD_RESTART
            restart_restoration(model)
          when RESTORE_METHOD_CUT_OFF
            cut_off_restoration(model)
          else
            raise ArgumentError, "Unknown restoration method: #{@method_type}"
          end
        end

        private

        # RESTART method: Reinitialize the model from scratch
        #
        # @param model [Model] The model to restore
        # @return [void]
        def restart_restoration(model)
          model.reset
        end

        # CUT_OFF method: Remove older contexts to free memory
        #
        # @param model [Model] The model to restore
        # @return [void]
        def cut_off_restoration(model)
          model.cut_off_old_contexts
        end
      end
    end
  end
end
