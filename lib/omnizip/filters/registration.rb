# frozen_string_literal: true

# Filter registration - triggers autoload and registers all filters
# This file should be required after filters.rb which sets up autoloads

module Omnizip
  module Filters
    # Touch constants to trigger autoload
    BCJ
    BcjX86
    Bcj2
    BcjArm
    BcjArm64
    BcjPpc
    BcjSparc
    BcjIa64
    Delta
  end
end

# Filter registration is handled by each filter class in their initialize methods
# via FilterRegistry.register calls
