# frozen_string_literal: true

require "action_dispatch"

require "oapi"
require "oapi-runtime"
require "fileutils"
require "pathname"
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)
end
