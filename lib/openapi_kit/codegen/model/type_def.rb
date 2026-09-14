# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Model
      class Property < T::Struct
        const :name, String
        const :identifier, Symbol
        const :schema, Schema
        const :required, T::Boolean, default: false
      end

      module UnionTag
        extend T::Helpers
        include Kernel
        sealed!
      end

      class Tagged < T::Struct
        include UnionTag
        const :property_name, String
        const :mapping, T::Hash[String, String]
      end

      class Untagged < T::Struct
        include UnionTag
      end

      module TypeDef
        extend T::Sig
        extend T::Helpers
        include Kernel
        sealed!

        sig { params(type_def: TypeDef).returns(String) }
        def self.name_of(type_def)
          case type_def
          when ObjectDef, FormDef, EnumDef, UnionDef, AliasDef then type_def.name
          else T.absurd(type_def)
          end
        end
      end

      class ObjectDef < T::Struct
        include TypeDef
        const :name, String
        const :properties, T::Array[Property]
        const :additional_properties, T.nilable(Schema), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class FormDef < T::Struct
        include TypeDef
        const :name, String
        const :properties, T::Array[Property]
        const :additional_properties, T.nilable(Schema), default: nil
        const :meta, Meta, factory: -> { Meta.new }
      end

      class EnumMember < T::Struct
        const :constant, String
        const :value, T.any(String, Integer)
      end

      class EnumDef < T::Struct
        include TypeDef
        const :name, String
        const :members, T::Array[EnumMember]
        const :meta, Meta, factory: -> { Meta.new }
      end

      class UnionDef < T::Struct
        include TypeDef
        const :name, String
        const :members, T::Array[Schema]
        const :tag, UnionTag
        const :meta, Meta, factory: -> { Meta.new }
      end

      class AliasDef < T::Struct
        include TypeDef
        const :name, String
        const :target, Schema
        const :meta, Meta, factory: -> { Meta.new }
      end
    end
  end
end
