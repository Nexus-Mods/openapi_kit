# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

module Oapi
  module Coders
    UUID = T.let(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, Regexp)

    module Untyped
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(T.untyped) }
      def self.load(value) = value

      sig { override.params(value: T.untyped).returns(T.untyped) }
      def self.dump(value) = value
    end

    module String
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::String) }
      def self.load(value)
        return value if value.is_a?(::String)

        raise DecodeError.new("expected a string, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(::String) }
      def self.dump(value) = value
    end

    module Integer
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::Integer) }
      def self.load(value)
        return value if value.is_a?(::Integer)
        return value.to_i if value.is_a?(::String) && value.match?(/\A[+-]?\d+\z/)

        raise DecodeError.new("expected an integer, got #{value.inspect}")
      end

      sig { override.params(value: ::Integer).returns(::Integer) }
      def self.dump(value) = value
    end

    module Float
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::Float) }
      def self.load(value)
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

      sig { override.params(value: ::Float).returns(::Float) }
      def self.dump(value) = value
    end

    module Decimal
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::BigDecimal) }
      def self.load(value)
        return value if value.is_a?(::BigDecimal)
        return Kernel.BigDecimal(value, 0) if value.is_a?(::Numeric)

        if value.is_a?(::String)
          begin
            return Kernel.BigDecimal(value)
          rescue ArgumentError, TypeError
            raise DecodeError.new("expected a decimal, got #{value.inspect}")
          end
        end

        raise DecodeError.new("expected a decimal, got #{value.inspect}")
      end

      sig { override.params(value: ::BigDecimal).returns(::String) }
      def self.dump(value) = value.to_s("F")
    end

    module Boolean
      extend T::Sig
      extend Coder

      TRUTHY = T.let(%w[true 1].freeze, T::Array[::String])
      FALSEY = T.let(%w[false 0].freeze, T::Array[::String])

      sig { override.params(value: Oapi::Wire).returns(T::Boolean) }
      def self.load(value)
        return value if value.is_a?(::TrueClass) || value.is_a?(::FalseClass)

        if value.is_a?(::String)
          return true if TRUTHY.include?(value.downcase)
          return false if FALSEY.include?(value.downcase)
        end

        raise DecodeError.new("expected a boolean, got #{value.inspect}")
      end

      sig { override.params(value: T::Boolean).returns(T::Boolean) }
      def self.dump(value) = value
    end

    module DateTime
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::Time) }
      def self.load(value)
        raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}") unless
          value.is_a?(::String)

        begin
          ::Time.iso8601(value)
        rescue ArgumentError
          raise DecodeError.new("expected an RFC 3339 date-time, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::Time).returns(::String) }
      def self.dump(value) = value.utc.iso8601
    end

    module Date
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::Date) }
      def self.load(value)
        raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}") unless
          value.is_a?(::String)

        begin
          ::Date.iso8601(value)
        rescue ::Date::Error
          raise DecodeError.new("expected an ISO 8601 date, got #{value.inspect}")
        end
      end

      sig { override.params(value: ::Date).returns(::String) }
      def self.dump(value) = value.iso8601
    end

    module Uuid
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::String) }
      def self.load(value)
        return value if value.is_a?(::String) && value.match?(UUID)

        raise DecodeError.new("expected a UUID, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(::String) }
      def self.dump(value) = value
    end

    module Byte
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(::String) }
      def self.load(value)
        raise DecodeError.new("expected base64, got #{value.inspect}") unless value.is_a?(::String)

        decoded = value.unpack1("m0")
        raise DecodeError.new("expected base64, got #{value.inspect}") if decoded.nil?

        decoded
      rescue ArgumentError
        raise DecodeError.new("expected base64, got #{value.inspect}")
      end

      sig { override.params(value: ::String).returns(::String) }
      def self.dump(value) = [value].pack("m0")
    end

    module Binary
      extend T::Sig
      extend Coder

      sig { override.params(value: Oapi::Wire).returns(UploadedFile) }
      def self.load(value)
        return value if value.is_a?(UploadedFile)
        return UploadedFile.new(io: value) if value.respond_to?(:read)

        raise DecodeError.new("expected an uploaded file, got #{value.class}")
      end

      sig { override.params(value: UploadedFile).returns(T.untyped) }
      def self.dump(value) = value.io
    end
  end
end
