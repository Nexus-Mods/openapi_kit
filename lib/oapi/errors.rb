# typed: strict
# frozen_string_literal: true

module Oapi
  class Error < StandardError; end

  class ConfigError < Error; end

  class SchemaError < Error; end

  class Unauthenticated < Error; end

  class DecodeError < Error
    extend T::Sig

    ROOT = T.let("", String)

    sig { returns(String) }
    attr_reader :json_pointer

    sig { returns(String) }
    attr_reader :detail

    sig { params(detail: String, json_pointer: String).void }
    def initialize(detail, json_pointer: ROOT)
      @detail = detail
      @json_pointer = json_pointer
      super(json_pointer == ROOT ? detail : "#{json_pointer}: #{detail}")
    end

    sig { params(prefix: String).returns(DecodeError) }
    def at(prefix) = DecodeError.new(detail, json_pointer: "#{prefix}#{json_pointer}")
  end
end
