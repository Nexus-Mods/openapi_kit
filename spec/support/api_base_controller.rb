# frozen_string_literal: true

require "action_controller"

# Generated controllers inherit the class named by `controller_base`, which the
# application owns. They call #oapi_container on it, and #oapi_authenticate! for any
# operation the document says needs authenticating.
class ApiBaseController < ActionController::API
  private

  def oapi_authenticate!(requirements); end
end
