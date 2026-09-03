# frozen_string_literal: true

require "action_controller"

# Generated controllers inherit the class named by `controller_base`, which the
# application owns. They read handlers and authenticators from Registry.current.
class ApiBaseController < ActionController::API
end
