# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

module Oapi
  Wire = T.type_alias do
    T.any(NilClass, String, Integer, Float, T::Boolean,
          T::Array[T.untyped], T::Hash[String, T.untyped])
  end

  module Codec
    extend T::Sig
    extend T::Generic
    extend T::Helpers
    interface!

    Value = type_member

    sig { abstract.params(value: T.untyped).returns(Value) }
    def from_wire(value); end

    sig { abstract.params(value: Value).returns(Oapi::Wire) }
    def to_wire(value); end

    module Primitive
      UUID = T.let(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, Regexp)

      class Untyped
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: T.untyped } }

        sig { override.params(value: T.untyped).returns(T.untyped) }
        def from_wire(value) = value

        sig { override.params(value: T.untyped).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, Untyped)
      end

      class String
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::String } }

        sig { override.params(value: T.untyped).returns(::String) }
        def from_wire(value)
          return value if value.is_a?(::String)

          raise DecodeError.new("expected a string, got #{value.inspect}")
        end

        sig { override.params(value: ::String).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, String)
      end

      class Integer
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::Integer } }

        sig { override.params(value: T.untyped).returns(::Integer) }
        def from_wire(value)
          return value if value.is_a?(::Integer)
          return value.to_i if value.is_a?(::String) && value.match?(/\A[+-]?\d+\z/)

          raise DecodeError.new("expected an integer, got #{value.inspect}")
        end

        sig { override.params(value: ::Integer).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, Integer)
      end

      class Float
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::Float } }

        sig { override.params(value: T.untyped).returns(::Float) }
        def from_wire(value)
          return value.to_f if value.is_a?(::Numeric)

          if value.is_a?(::String)
            begin
              return Kernel.Float(value)
            rescue ArgumentError, TypeError
              raise DecodeError.new("expected a number, got #{value.inspect}")
            end
          end

          raise DecodeError.new("expected a number, got #{value.inspect}")
        end

        sig { override.params(value: ::Float).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, Float)
      end

      class Decimal
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::BigDecimal } }

        sig { override.params(value: T.untyped).returns(::BigDecimal) }
        def from_wire(value)
          case value
          when ::Integer then Kernel.BigDecimal(value)
          when ::Float then Kernel.BigDecimal(value, ::Float::DIG)
          when ::String
            begin
              Kernel.BigDecimal(value)
            rescue ArgumentError, TypeError
              raise DecodeError.new("expected a decimal, got #{value.inspect}")
            end
          else raise DecodeError.new("expected a decimal, got #{value.inspect}")
          end
        end

        sig { override.params(value: ::BigDecimal).returns(Oapi::Wire) }
        def to_wire(value) = value.to_s("F")

        INSTANCE = T.let(new, Decimal)
      end

      class Boolean
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: T::Boolean } }

        TRUTHY = T.let(%w[true 1].freeze, T::Array[::String])
        FALSEY = T.let(%w[false 0].freeze, T::Array[::String])

        sig { override.params(value: T.untyped).returns(T::Boolean) }
        def from_wire(value)
          return value if value.is_a?(::TrueClass) || value.is_a?(::FalseClass)

          if value.is_a?(::String)
            return true if TRUTHY.include?(value.downcase)
            return false if FALSEY.include?(value.downcase)
          end

          raise DecodeError.new("expected a boolean, got #{value.inspect}")
        end

        sig { override.params(value: T::Boolean).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, Boolean)
      end

      class DateTime
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::Time } }

        sig { override.params(value: T.untyped).returns(::Time) }
        def from_wire(value)
          raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}") unless
            value.is_a?(::String)

          begin
            ::Time.iso8601(value)
          rescue ArgumentError
            raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}")
          end
        end

        sig { override.params(value: ::Time).returns(Oapi::Wire) }
        def to_wire(value) = value.utc.iso8601

        INSTANCE = T.let(new, DateTime)
      end

      class Date
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::Date } }

        sig { override.params(value: T.untyped).returns(::Date) }
        def from_wire(value)
          raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}") unless value.is_a?(::String)

          begin
            ::Date.iso8601(value)
          rescue ::Date::Error
            raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}")
          end
        end

        sig { override.params(value: ::Date).returns(Oapi::Wire) }
        def to_wire(value) = value.iso8601

        INSTANCE = T.let(new, Date)
      end

      class Uuid
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::String } }

        sig { override.params(value: T.untyped).returns(::String) }
        def from_wire(value)
          return value if value.is_a?(::String) && value.match?(UUID)

          raise DecodeError.new("expected a UUID, got #{value.inspect}")
        end

        sig { override.params(value: ::String).returns(Oapi::Wire) }
        def to_wire(value) = value

        INSTANCE = T.let(new, Uuid)
      end

      class Byte
        extend T::Sig
        extend T::Generic
        include Oapi::Codec

        Value = type_member { { fixed: ::String } }

        sig { override.params(value: T.untyped).returns(::String) }
        def from_wire(value)
          raise DecodeError.new("expected base64, got #{value.inspect}") unless value.is_a?(::String)

          decoded = value.unpack1("m0")
          raise DecodeError.new("expected base64, got #{value.inspect}") if decoded.nil?

          decoded
        rescue ArgumentError
          raise DecodeError.new("expected base64, got #{value.inspect}")
        end

        sig { override.params(value: ::String).returns(Oapi::Wire) }
        def to_wire(value) = [value].pack("m0")

        INSTANCE = T.let(new, Byte)
      end
    end
  end
end
