# typed: strict
# frozen_string_literal: true

class ApiBaseController < ActionController::API
  extend T::Sig

  private

  sig { returns(T.untyped) }
  def oapi_container = ObjectSpace

  sig { params(requirements: T::Array[Oapi::Security::Requirement]).void }
  def oapi_authenticate!(requirements); end
end
