# typed: strict
# frozen_string_literal: true

module Oapi
  class Framework < T::Enum
    extend T::Sig

    enums do
      Rails = new("rails")
      Rack = new("rack")
    end

    REQUEST_TYPES = T.let(
      {
        "rails" => "::ActionDispatch::Request",
        "rack" => "::Rack::Request"
      }.freeze,
      T::Hash[String, String]
    )

    TYPE_MAPPINGS = T.let(
      {
        "rails" => {
          "string:binary" => RubyType.new(
            type: "::ActionDispatch::Http::UploadedFile",
            codec: "::Oapi::Rails::Codec::UploadedFile"
          )
        }.freeze,
        "rack" => {}.freeze
      }.freeze,
      T::Hash[String, T::Hash[String, RubyType]]
    )

    REQUIRES = T.let({ "rails" => "oapi/rails" }.freeze, T::Hash[String, String])

    sig { returns(String) }
    def request_type = T.must(REQUEST_TYPES[serialize])

    sig { returns(T::Hash[String, RubyType]) }
    def type_mappings = T.must(TYPE_MAPPINGS[serialize])

    sig { returns(T.nilable(String)) }
    def runtime_require = REQUIRES[serialize]

    sig { params(value: T.untyped).returns(Framework) }
    def self.parse(value)
      found = try_deserialize(value.to_s)
      return found if found

      raise ConfigError,
            "`framework` is #{value.inspect}. Valid values: #{values.map(&:serialize).join(", ")}. " \
            "Omit it to generate no framework request field."
    end
  end
end
