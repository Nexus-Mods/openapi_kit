# typed: strict
# frozen_string_literal: true

require "openapi_kit/body"

module OpenAPIKit
  module Response
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(::Integer) }
    def status; end

    sig { abstract.returns(OpenAPIKit::Body) }
    def to_body; end

    sig { abstract.returns(T.nilable(::String)) }
    def content_type; end
  end
end
