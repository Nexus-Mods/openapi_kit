# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Ir
      class Default < T::Struct
        const :value, T.untyped
      end

      class Meta < T::Struct
        const :description, T.nilable(String), default: nil
        const :nullable, T::Boolean, default: false
        const :deprecated, T::Boolean, default: false
        const :default, T.nilable(Default), default: nil
        const :read_only, T::Boolean, default: false
        const :write_only, T::Boolean, default: false
        const :extensions, T::Hash[String, T.untyped], default: {}
        const :ruby_type, T.nilable(RubyType), default: nil
      end

      module Schema
        extend T::Sig
        extend T::Helpers
        include Kernel
        sealed!

        sig { params(schema: Schema).returns(Meta) }
        def self.meta(schema)
          case schema
          when Ref, StringSchema, IntegerSchema, NumberSchema, BooleanSchema, List, Freeform, Untyped
            schema.meta
          else T.absurd(schema)
          end
        end

        sig { params(schema: Schema).returns(T::Boolean) }
        def self.nullable?(schema) = meta(schema).nullable
      end

      class Ref < T::Struct
        include Schema
        const :name, String
        const :meta, Meta, factory: -> { Meta.new }
      end

      class StringSchema < T::Struct
        include Schema
        const :format, T.nilable(String), default: nil
        const :min_length, T.nilable(Integer), default: nil
        const :max_length, T.nilable(Integer), default: nil
        const :pattern, T.nilable(String), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class IntegerSchema < T::Struct
        include Schema
        const :format, T.nilable(String), default: nil
        const :minimum, T.nilable(Integer), default: nil
        const :maximum, T.nilable(Integer), default: nil
        const :exclusive_minimum, T::Boolean, default: false
        const :exclusive_maximum, T::Boolean, default: false
        const :multiple_of, T.nilable(Integer), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class NumberSchema < T::Struct
        include Schema
        const :format, T.nilable(String), default: nil
        const :minimum, T.nilable(Numeric), default: nil
        const :maximum, T.nilable(Numeric), default: nil
        const :exclusive_minimum, T::Boolean, default: false
        const :exclusive_maximum, T::Boolean, default: false
        const :multiple_of, T.nilable(Numeric), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class BooleanSchema < T::Struct
        include Schema
        const :meta, Meta, factory: -> { Meta.new }
      end

      class List < T::Struct
        include Schema
        const :items, Schema
        const :min_items, T.nilable(Integer), default: nil
        const :max_items, T.nilable(Integer), default: nil
        const :unique_items, T::Boolean, default: false
        const :meta, Meta, factory: -> { Meta.new }
      end

      class Freeform < T::Struct
        include Schema
        const :values, T.nilable(Schema), default: nil
        const :min_properties, T.nilable(Integer), default: nil
        const :max_properties, T.nilable(Integer), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class Untyped < T::Struct
        include Schema
        const :meta, Meta, factory: -> { Meta.new }
      end
    end
  end
end
