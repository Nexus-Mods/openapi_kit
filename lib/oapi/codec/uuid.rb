# typed: strict
# frozen_string_literal: true

require "oapi/codec/contract"

module Oapi
  module Codec
    module Uuid
      extend T::Sig
      extend T::Generic
      extend Contract

      Value = type_template { { fixed: ::String } }

      PATTERN = T.let(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, Regexp)

      sig { override.params(value: Oapi::Wire).returns(::String) }
      def self.from_wire(value)
        return value if value.is_a?(::String) && value.match?(PATTERN)

        raise DecodeError.new("expected a UUID, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(Oapi::Wire) }
      def self.to_wire(value) = value
    end
  end
end
