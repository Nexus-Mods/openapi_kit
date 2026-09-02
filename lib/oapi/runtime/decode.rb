# typed: strict
# frozen_string_literal: true

module Oapi
  module Decode
    extend T::Sig

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String, pointer: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.field(raw, key, pointer, &block)
      value = raw[key]
      raise DecodeError.new("is required", pointer: "#{pointer}/#{key}") if value.nil?

      at("#{pointer}/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String, pointer: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.nilable(T.type_parameter(:T)))
    end
    def self.optional(raw, key, pointer, &block)
      value = raw[key]
      return nil if value.nil?

      at("#{pointer}/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String, pointer: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(Oapi::Optional[T.nilable(T.type_parameter(:T))])
    end
    def self.tristate(raw, key, pointer, &block)
      return Absent::INSTANCE unless raw.key?(key)

      value = raw[key]
      return Present.new(value: nil) if value.nil?

      Present.new(value: at("#{pointer}/#{key}") { block.call(value) })
    end

    sig do
      type_parameters(:T)
        .params(pointer: String, block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.at(pointer, &block)
      block.call
    rescue DecodeError => e
      raise e.at(pointer)
    rescue ArgumentError, TypeError => e
      raise DecodeError.new(e.message, pointer: pointer)
    end

    sig { params(raw: T.untyped, pointer: String).returns(T::Hash[String, T.untyped]) }
    def self.object(raw, pointer = "")
      return raw if raw.is_a?(Hash)

      raise DecodeError.new("expected an object, got #{raw.class}", pointer: pointer)
    end

    sig { params(raw: T.untyped, pointer: String).returns(T::Array[T.untyped]) }
    def self.array(raw, pointer = "")
      return raw if raw.is_a?(Array)

      raise DecodeError.new("expected an array, got #{raw.class}", pointer: pointer)
    end

    sig do
      type_parameters(:T)
        .params(raw: T.untyped, pointer: String,
                block: T.proc.params(item: T.untyped, item_pointer: String).returns(T.type_parameter(:T)))
        .returns(T::Array[T.type_parameter(:T)])
    end
    def self.each(raw, pointer, &block)
      array(raw, pointer).each_with_index.map { |item, index| block.call(item, "#{pointer}/#{index}") }
    end
  end
end
