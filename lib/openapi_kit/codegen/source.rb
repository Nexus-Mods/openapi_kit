# typed: strict
# frozen_string_literal: true

require "yaml"

module OpenAPIKit
  module Codegen
    # What the Loader reads from a document. Each OpenAPI version is read by its own source,
    # under its own schema dialect: Source::Openapi30 through openapi3_parser.
    module Source
      extend T::Sig

      sig { params(path: Pathname).returns(Document) }
      def self.load(path)
        data = YAML.safe_load_file(path.to_s, permitted_classes: [Date, Time], aliases: true)
        version = data.is_a?(Hash) ? data["openapi"].to_s : ""

        case version
        when /\A3\.0\./ then Openapi30.load(path)
        else
          raise SchemaError, "#{path} declares openapi: #{version.inspect}. openapi_kit reads OpenAPI 3.0."
        end
      end

      class Discriminator < T::Struct
        const :property_name, String
        const :mapping, T.nilable(T::Hash[String, String])
      end

      module Document
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(String) }
        def title; end

        sig { abstract.returns(String) }
        def version; end

        sig { abstract.returns(T::Array[[String, PathItem]]) }
        def paths; end

        sig { abstract.returns(T::Array[[String, Schema]]) }
        def schemas; end

        sig { abstract.returns(T::Array[[String, SecurityScheme]]) }
        def security_schemes; end

        sig { abstract.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
        def security; end
      end

      module PathItem
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        # Each operation with its method, in the order the Loader routes them.
        sig { abstract.returns(T::Array[[String, Operation]]) }
        def operations; end

        sig { abstract.returns(T::Array[Parameter]) }
        def parameters; end
      end

      module Operation
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(T.nilable(String)) }
        def operation_id; end

        sig { abstract.returns(T::Array[String]) }
        def tags; end

        sig { abstract.returns(T::Array[Parameter]) }
        def parameters; end

        sig { abstract.returns(T.nilable(RequestBody)) }
        def request_body; end

        sig { abstract.returns(T::Array[[String, Response]]) }
        def responses; end

        # nil when the operation leaves security to the document.
        sig { abstract.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
        def security; end

        sig { abstract.returns(T.nilable(String)) }
        def summary; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end

        sig { abstract.returns(T::Boolean) }
        def deprecated?; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def extensions; end
      end

      module Parameter
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(String) }
        def name; end

        sig { abstract.returns(String) }
        def location; end

        sig { abstract.returns(T::Boolean) }
        def required?; end

        sig { abstract.returns(T.nilable(String)) }
        def style; end

        # nil when the document leaves explode to the style's default.
        sig { abstract.returns(T.nilable(T::Boolean)) }
        def explode; end

        sig { abstract.returns(T::Boolean) }
        def allow_reserved?; end

        sig { abstract.returns(T.nilable(Schema)) }
        def schema; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end

        sig { abstract.returns(T::Boolean) }
        def deprecated?; end
      end

      module RequestBody
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        # Each media type with its schema, if it declares one.
        sig { abstract.returns(T::Array[[String, T.nilable(Schema)]]) }
        def content; end

        sig { abstract.returns(T::Boolean) }
        def required?; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end
      end

      module Response
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(T::Array[[String, T.nilable(Schema)]]) }
        def content; end

        sig { abstract.returns(T::Array[[String, Header]]) }
        def headers; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end
      end

      module Header
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(T.nilable(Schema)) }
        def schema; end

        sig { abstract.returns(T::Boolean) }
        def required?; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end
      end

      module SecurityScheme
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        sig { abstract.returns(T.nilable(String)) }
        def type; end

        sig { abstract.returns(T.nilable(String)) }
        def name; end

        sig { abstract.returns(T.nilable(String)) }
        def location; end

        sig { abstract.returns(T.nilable(String)) }
        def scheme; end

        sig { abstract.returns(T.nilable(String)) }
        def bearer_format; end

        # The scopes of each OAuth flow the scheme declares, in the order the flows are listed
        # in the specification: implicit, password, clientCredentials, authorizationCode.
        sig { abstract.returns(T::Array[T::Hash[String, String]]) }
        def flow_scopes; end

        sig { abstract.returns(T.nilable(String)) }
        def open_id_connect_url; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def extensions; end
      end

      # A schema as the Loader sees it, whichever dialect it was written in.
      module Schema
        extend T::Sig
        extend T::Helpers
        include Kernel
        interface!

        # The components/schemas name, for a schema defined there.
        sig { abstract.returns(T.nilable(String)) }
        def name; end

        # Where the schema is defined, unique across the files a document spans.
        sig { abstract.returns(String) }
        def key; end

        # The single non-null type, if the schema states one.
        sig { abstract.returns(T.nilable(String)) }
        def type; end

        sig { abstract.returns(T::Boolean) }
        def nullable?; end

        sig { abstract.returns(T.nilable(String)) }
        def type_format; end

        sig { abstract.returns(T.nilable(T::Array[T.untyped])) }
        def enum; end

        sig { abstract.returns(T::Boolean) }
        def default?; end

        sig { abstract.returns(T.untyped) }
        def default; end

        sig { abstract.returns(T.nilable(String)) }
        def description; end

        sig { abstract.returns(T::Boolean) }
        def deprecated?; end

        sig { abstract.returns(T::Boolean) }
        def read_only?; end

        sig { abstract.returns(T::Boolean) }
        def write_only?; end

        sig { abstract.returns(T.nilable(T::Array[Schema])) }
        def all_of; end

        sig { abstract.returns(T.nilable(T::Array[Schema])) }
        def one_of; end

        sig { abstract.returns(T.nilable(T::Array[Schema])) }
        def any_of; end

        sig { abstract.returns(T.nilable(Discriminator)) }
        def discriminator; end

        sig { abstract.returns(T.nilable(T::Array[[String, Schema]])) }
        def properties; end

        sig { abstract.returns(T::Array[String]) }
        def required; end

        sig { abstract.returns(T.nilable(Schema)) }
        def additional_properties; end

        sig { abstract.returns(T.nilable(Schema)) }
        def items; end

        sig { abstract.returns(T.nilable(Integer)) }
        def min_length; end

        sig { abstract.returns(T.nilable(Integer)) }
        def max_length; end

        sig { abstract.returns(T.nilable(String)) }
        def pattern; end

        sig { abstract.returns(T.nilable(Numeric)) }
        def minimum; end

        sig { abstract.returns(T.nilable(Numeric)) }
        def maximum; end

        sig { abstract.returns(T::Boolean) }
        def exclusive_minimum?; end

        sig { abstract.returns(T::Boolean) }
        def exclusive_maximum?; end

        sig { abstract.returns(T.nilable(Numeric)) }
        def multiple_of; end

        sig { abstract.returns(T.nilable(Integer)) }
        def min_items; end

        sig { abstract.returns(T.nilable(Integer)) }
        def max_items; end

        sig { abstract.returns(T::Boolean) }
        def unique_items?; end

        sig { abstract.returns(T.nilable(Integer)) }
        def min_properties; end

        sig { abstract.returns(T.nilable(Integer)) }
        def max_properties; end

        sig { abstract.returns(T::Hash[String, T.untyped]) }
        def extensions; end
      end
    end
  end
end
