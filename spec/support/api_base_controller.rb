# frozen_string_literal: true

require "action_controller"

# Generated controllers inherit the class named by `controller_base`, which the
# application owns, and call #oapi_container on it to reach the handlers and
# authenticators it registered.
class ApiBaseController < ActionController::API
end
