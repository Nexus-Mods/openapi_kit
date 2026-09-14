# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Optional
    extend T::Sig
    extend T::Generic
    include Kernel
    abstract!
    sealed!

    Value = type_member

    sig { abstract.params(fallback: Value).returns(Value) }
    def value_or(fallback); end
  end

  class Present
    extend T::Sig
    extend T::Generic
    include Optional

    Value = type_member

    sig { returns(Value) }
    attr_reader :value

    sig { params(value: Value).void }
    def initialize(value)
      @value = value
    end

    sig { override.params(fallback: Value).returns(Value) }
    def value_or(fallback) = value

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other) = other.is_a?(Present) && T.unsafe(other).value == T.unsafe(self).value

    sig { params(other: T.untyped).returns(T::Boolean) }
    def eql?(other) = self == other

    sig { returns(Integer) }
    def hash = [Present, T.unsafe(self).value].hash
  end

  class Absent
    extend T::Sig
    extend T::Generic
    include Optional

    Value = type_member

    sig { override.params(fallback: Value).returns(Value) }
    def value_or(fallback) = fallback

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other) = other.is_a?(Absent)

    sig { params(other: T.untyped).returns(T::Boolean) }
    def eql?(other) = self == other

    sig { returns(Integer) }
    def hash = Absent.hash
  end

  ABSENT = T.let(Absent.new.freeze, Absent[T.untyped])
end
