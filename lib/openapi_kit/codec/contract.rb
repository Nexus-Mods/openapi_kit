# typed: strict
# frozen_string_literal: true

require "openapi_kit/wire"

module OpenAPIKit
  module Codec
    module Contract
      extend T::Sig
      extend T::Generic
      interface!

      Value = type_member

      sig { abstract.params(value: OpenAPIKit::Wire).returns(Value) }
      def from_wire(value); end

      sig { abstract.params(value: Value).returns(OpenAPIKit::Wire) }
      def to_wire(value); end
    end
  end
end
