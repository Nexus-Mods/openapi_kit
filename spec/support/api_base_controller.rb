# frozen_string_literal: true

require "action_controller"

# Generated controllers inherit the class named by `controller_base`, which the
# application owns, and read their handlers and authenticators off #oapi_registry.
class ApiBaseController < ActionController::API
end
