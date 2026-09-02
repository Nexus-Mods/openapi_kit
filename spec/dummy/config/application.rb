# frozen_string_literal: true

require "action_controller/railtie"

require "oapi/runtime"

module Dummy
  class Application < ::Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "dummy"
    config.logger = Logger.new(IO::NULL)
    config.hosts.clear
  end
end
