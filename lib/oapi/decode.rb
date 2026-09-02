# typed: strict
# frozen_string_literal: true

module Oapi
  module Decode
    extend T::Sig

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.field(raw, key, &block)
      value = raw[key]
      raise DecodeError.new("is required", json_pointer: "/#{key}") if value.nil?

      at("/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.nilable(T.type_parameter(:T)))
    end
    def self.nullable_field(raw, key, &block)
      raise DecodeError.new("is required", json_pointer: "/#{key}") unless raw.key?(key)

      value = raw[key]
      return nil if value.nil?

      at("/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String, fallback: T.type_parameter(:T),
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.defaulted(raw, key, fallback, &block)
      value = raw[key]
      return fallback if value.nil?

      at("/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(T.nilable(T.type_parameter(:T)))
    end
    def self.optional(raw, key, &block)
      value = raw[key]
      return nil if value.nil?

      at("/#{key}") { block.call(value) }
    end

    sig do
      type_parameters(:T)
        .params(raw: T::Hash[String, T.untyped], key: String,
                block: T.proc.params(value: T.untyped).returns(T.type_parameter(:T)))
        .returns(Oapi::Optional[T.nilable(T.type_parameter(:T))])
    end
    def self.tristate(raw, key, &block)
      return Absent[T.nilable(T.type_parameter(:T))].new unless raw.key?(key)

      value = raw[key]
      return Present[T.nilable(T.type_parameter(:T))].new(value: nil) if value.nil?

      Present[T.nilable(T.type_parameter(:T))].new(value: at("/#{key}") { block.call(value) })
    end

    sig do
      type_parameters(:T)
        .params(raw: T.untyped, block: T.proc.params(item: T.untyped).returns(T.type_parameter(:T)))
        .returns(T::Array[T.type_parameter(:T)])
    end
    def self.each(raw, &block)
      array(raw).each_with_index.map { |item, index| at("/#{index}") { block.call(item) } }
    end

    sig do
      type_parameters(:T)
        .params(raw: T.untyped, block: T.proc.params(item: T.untyped).returns(T.type_parameter(:T)))
        .returns(T::Hash[String, T.type_parameter(:T)])
    end
    def self.values(raw, &block)
      object(raw).to_h { |key, item| [key, at("/#{key}") { block.call(item) }] }
    end

    sig do
      type_parameters(:T)
        .params(prefix: String, block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.at(prefix, &block)
      block.call
    rescue DecodeError => e
      raise e.at(prefix)
    rescue ArgumentError, TypeError => e
      raise DecodeError.new(e.message, json_pointer: prefix)
    end

    sig { params(source: T.untyped, names: T::Array[String]).returns(T::Hash[String, String]) }
    def self.gather(source, names)
      names.each_with_object({}) do |name, found|
        value = source[name]
        found[name] = value.to_s unless value.nil?
      end
    end

    sig { params(raw: T.untyped).returns(T::Hash[String, T.untyped]) }
    def self.object(raw)
      return raw if raw.is_a?(Hash)

      raise DecodeError.new("expected an object, got #{raw.class}")
    end

    sig do
      params(value: T.untyped, name: String,
             candidates: T::Array[T.proc.params(value: T.untyped).returns(T.untyped)])
        .returns(T.untyped)
    end
    def self.first_of(value, name, candidates)
      candidates.each do |candidate|
        return candidate.call(value)
      rescue DecodeError
        next
      end

      raise DecodeError.new("did not match any member of #{name}")
    end

    sig { params(raw: T.untyped).returns(T::Array[T.untyped]) }
    def self.array(raw)
      return raw if raw.is_a?(Array)

      raise DecodeError.new("expected an array, got #{raw.class}")
    end
  end
end
