# typed: strict
# frozen_string_literal: true

module Oapi
  class TypeRegistry
    module Defaults
      extend T::Sig

      sig { params(type: T.any(T::Module[T.anything], String), codec: T.untyped).returns(RubyType) }
      def self.entry(type, codec)
        RubyType.new(
          type: type.is_a?(::Module) ? "::#{T.must(type.name)}" : type,
          codec: "::Oapi::Codec::Scalar::#{constant_holding(codec)}"
        )
      end

      sig { params(codec: T.untyped).returns(Symbol) }
      def self.constant_holding(codec)
        found = Oapi::Codec::Scalar.constants.find { |name| Oapi::Codec::Scalar.const_get(name).equal?(codec) }
        return found if found

        raise Error, "#{codec.class} is not held by any constant under Oapi::Codec::Scalar"
      end

      BASES = T.let(
        {
          "string" => entry(::String, Oapi::Codec::Scalar::String),
          "integer" => entry(::Integer, Oapi::Codec::Scalar::Integer),
          "number" => entry(::Float, Oapi::Codec::Scalar::Float),
          "boolean" => entry("T::Boolean", Oapi::Codec::Scalar::Boolean)
        }.freeze,
        T::Hash[String, RubyType]
      )

      FORMATS_WITHOUT_OWN_TYPE = T.let(
        {
          "string" => %w[
            time duration email idn-email hostname idn-hostname ipv4 ipv6
            uri uri-reference uri-template iri json-pointer relative-json-pointer
            regex password
          ],
          "integer" => %w[int32 int64],
          "number" => %w[float double]
        }.freeze,
        T::Hash[String, T::Array[String]]
      )

      FORMATS_WITH_OWN_TYPE = T.let(
        {
          "string:date-time" => entry(::Time, Oapi::Codec::Scalar::DateTime),
          "string:date" => entry(::Date, Oapi::Codec::Scalar::Date),
          "string:uuid" => entry(::String, Oapi::Codec::Scalar::Uuid),
          "string:byte" => entry(::String, Oapi::Codec::Scalar::Byte),
          "string:binary" => RubyType.new(
            type: "::ActionDispatch::Http::UploadedFile",
            codec: "::Oapi::Rails::Codec::UploadedFile"
          ),
          "string:decimal" => entry(::BigDecimal, Oapi::Codec::Scalar::Decimal),
          "number:decimal" => entry(::BigDecimal, Oapi::Codec::Scalar::Decimal)
        }.freeze,
        T::Hash[String, RubyType]
      )

      TABLE = T.let(
        BASES
          .merge(
            FORMATS_WITHOUT_OWN_TYPE.flat_map do |base, formats|
              formats.map { |format| ["#{base}:#{format}", T.must(BASES[base])] }
            end.to_h
          )
          .merge(FORMATS_WITH_OWN_TYPE)
          .freeze,
        T::Hash[String, RubyType]
      )

      sig { params(key: String).returns(T.nilable(RubyType)) }
      def self.[](key) = TABLE[key]
    end
  end
end
