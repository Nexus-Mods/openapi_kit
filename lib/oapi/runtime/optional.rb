# typed: strict
# frozen_string_literal: true

module Oapi
  module Optional
    extend T::Sig
    extend T::Generic
    extend T::Helpers
    abstract!
    sealed!

    Value = type_member(:out)

    sig { abstract.returns(T::Boolean) }
    def present?; end

    sig { abstract.params(fallback: Value).returns(Value) }
    def value_or(fallback); end
  end

  class Present
    extend T::Sig
    extend T::Generic
    include Optional

    Value = type_member(:out)

    sig { returns(Value) }
    attr_reader :value

    sig { params(value: Value).void }
    def initialize(value:)
      @value = value
    end

    sig { override.returns(T::Boolean) }
    def present? = true

    sig { override.params(fallback: Value).returns(Value) }
    def value_or(_fallback) = value

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other) = other.is_a?(Present) && other.value == value
  end

  class Absent
    extend T::Sig
    extend T::Generic
    include Optional

    Value = type_member(:out)

    sig { override.returns(T::Boolean) }
    def present? = false

    sig { override.params(fallback: Value).returns(Value) }
    def value_or(fallback) = fallback

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other) = other.is_a?(Absent)

    INSTANCE = T.let(new, Absent[T.untyped])
  end
end
