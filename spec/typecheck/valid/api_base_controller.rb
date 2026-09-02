# typed: strict
# frozen_string_literal: true

class ApiBaseController < ActionController::API
  extend T::Sig
  include Oapi::Rails::Rendering

  private

  sig { override.returns(T.untyped) }
  def oapi_container = ObjectSpace
end
