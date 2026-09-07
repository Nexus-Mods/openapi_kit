# typed: strict
# frozen_string_literal: true

require "oapi/body"

module Oapi
  module Response
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(::Integer) }
    def status; end

    sig { abstract.returns(Oapi::Body) }
    def to_body; end

    sig { abstract.returns(T.nilable(::String)) }
    def content_type; end
  end
end
