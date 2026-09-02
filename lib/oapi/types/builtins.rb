# typed: strict
# frozen_string_literal: true

module Oapi
  module Types
    module Builtins
      extend T::Sig

      BASES = T.let(
        {
          "string" => RubyType.new(type: "::String", coder: "Oapi::Coders::String"),
          "integer" => RubyType.new(type: "::Integer", coder: "Oapi::Coders::Integer"),
          "number" => RubyType.new(type: "::Float", coder: "Oapi::Coders::Float"),
          "boolean" => RubyType.new(type: "T::Boolean", coder: "Oapi::Coders::Boolean")
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

      DISTINCT = T.let(
        {
          "string:date-time" => RubyType.new(type: "::Time", coder: "Oapi::Coders::DateTime"),
          "string:date" => RubyType.new(type: "::Date", coder: "Oapi::Coders::Date"),
          "string:uuid" => RubyType.new(type: "::String", coder: "Oapi::Coders::Uuid"),
          "string:byte" => RubyType.new(type: "::String", coder: "Oapi::Coders::Byte"),
          "string:binary" => RubyType.new(type: "::Oapi::UploadedFile", coder: "Oapi::Coders::Binary"),
          "string:decimal" => RubyType.new(type: "::BigDecimal", coder: "Oapi::Coders::Decimal"),
          "number:decimal" => RubyType.new(type: "::BigDecimal", coder: "Oapi::Coders::Decimal")
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
          .merge(DISTINCT)
          .freeze,
        T::Hash[String, RubyType]
      )

      sig { params(key: String).returns(T.nilable(RubyType)) }
      def self.[](key) = TABLE[key]
    end
  end
end
