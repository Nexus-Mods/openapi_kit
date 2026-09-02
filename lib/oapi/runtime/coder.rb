# typed: strict
# frozen_string_literal: true

module Oapi
  module Coder
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.params(value: Oapi::Wire).returns(T.untyped) }
    def load(value); end

    sig { abstract.params(value: T.untyped).returns(Oapi::Wire) }
    def dump(value); end
  end
end
