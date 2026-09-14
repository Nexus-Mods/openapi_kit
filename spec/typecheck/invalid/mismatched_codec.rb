# typed: strict
# frozen_string_literal: true

class MismatchedCodec
  extend T::Sig
  extend T::Generic
  include OpenAPIKit::Codec::Contract

  Value = type_member { { fixed: ::Time } }

  sig { override.params(value: T.untyped).returns(::Time) }
  def from_wire(value) = ::Time.at(0)

  sig { override.params(value: ::String).returns(OpenAPIKit::Wire) }
  def to_wire(value) = value
end
