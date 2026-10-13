# typed: strict
# frozen_string_literal: true

require "openapi3_parser"

module OpenAPIKit
  module Codegen
    module Source
      # OpenAPI 3.0, read through openapi3_parser. Schemas follow 3.0's dialect: a single
      # `type` and the `nullable` keyword.
      module Openapi30
        extend T::Sig

        VERBS = T.let(%w[get put post delete options head patch trace].freeze, T::Array[String])
        OAUTH_FLOWS = T.let(
          %i[implicit password client_credentials authorization_code].freeze,
          T::Array[Symbol]
        )

        sig { params(path: Pathname).returns(Source::Document) }
        def self.load(path)
          document = Openapi3Parser.load_file(path)
          unless document.valid?
            details = document.errors.map { |e| "  #{e.context&.location_summary}: #{e.message}" }
            raise SchemaError, "#{path} is not a valid OpenAPI document:\n#{details.join("\n")}"
          end

          Document.new(document)
        end

        sig { params(node: Openapi3Parser::Node::Object).returns(T::Hash[String, T.untyped]) }
        def self.raw(node)
          input = node.node_context.input
          input.is_a?(Hash) ? input : {}
        end

        sig { params(node: Openapi3Parser::Node::Object).returns(T::Hash[String, T.untyped]) }
        def self.extensions(node) = raw(node).select { |k, _| k.to_s.start_with?("x-") }

        sig do
          params(node: T.any(Openapi3Parser::Document, Openapi3Parser::Node::Operation))
            .returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]]))
        end
        def self.requirements(node)
          node.security&.map { |requirement| requirement.to_h.transform_values { |scopes| Array(scopes).map(&:to_s) } }
        end

        sig do
          params(node: T.any(Openapi3Parser::Node::RequestBody, Openapi3Parser::Node::Response))
            .returns(T::Array[[String, T.nilable(Source::Schema)]])
        end
        def self.content(node)
          (node.content || []).map do |media_type, media|
            schema = media.schema
            [media_type, schema ? Schema.new(schema) : nil]
          end
        end

        class Document
          extend T::Sig
          include Source::Document

          sig { params(node: Openapi3Parser::Document).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(String) }
          def title = @node.info.title

          sig { override.returns(String) }
          def version = @node.info.version

          sig { override.returns(T::Array[[String, Source::PathItem]]) }
          def paths = @node.paths.map { |path, item| [path, PathItem.new(item)] }

          sig { override.returns(T::Array[[String, Source::Schema]]) }
          def schemas = (@node.components&.schemas || []).map { |name, node| [name, Schema.new(node)] }

          sig { override.returns(T::Array[[String, Source::SecurityScheme]]) }
          def security_schemes
            (@node.components&.security_schemes || []).map { |name, node| [name, SecurityScheme.new(node)] }
          end

          sig { override.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
          def security = Openapi30.requirements(@node)
        end

        class PathItem
          extend T::Sig
          include Source::PathItem

          sig { params(node: Openapi3Parser::Node::PathItem).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, Source::Operation]]) }
          def operations
            VERBS.filter_map do |verb|
              node = T.let(@node.public_send(verb), T.nilable(Openapi3Parser::Node::Operation))
              [verb, Operation.new(node)] if node
            end
          end

          sig { override.returns(T::Array[Source::Parameter]) }
          def parameters = @node.parameters.to_a.map { |node| Parameter.new(node) }
        end

        class Operation
          extend T::Sig
          include Source::Operation

          sig { params(node: Openapi3Parser::Node::Operation).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(String)) }
          def operation_id = @node.operation_id

          sig { override.returns(T::Array[String]) }
          def tags = @node.tags.to_a

          sig { override.returns(T::Array[Source::Parameter]) }
          def parameters = @node.parameters.to_a.map { |node| Parameter.new(node) }

          sig { override.returns(T.nilable(Source::RequestBody)) }
          def request_body = (body = @node.request_body) && RequestBody.new(body)

          sig { override.returns(T::Array[[String, Source::Response]]) }
          def responses = (@node.responses || []).map { |status, node| [status.to_s, Response.new(node)] }

          sig { override.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
          def security
            Openapi30.requirements(@node) if Openapi30.raw(@node).key?("security")
          end

          sig { override.returns(T.nilable(String)) }
          def summary = @node.summary

          sig { override.returns(T.nilable(String)) }
          def description = @node.description

          sig { override.returns(T::Boolean) }
          def deprecated? = !!@node.deprecated?

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = Openapi30.extensions(@node)
        end

        class Parameter
          extend T::Sig
          include Source::Parameter

          sig { params(node: Openapi3Parser::Node::Parameter).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(String) }
          def name = @node.name

          sig { override.returns(String) }
          def location = @node.in

          sig { override.returns(T::Boolean) }
          def required? = !!@node.required?

          sig { override.returns(T.nilable(String)) }
          def style = @node.style

          sig { override.returns(T.nilable(T::Boolean)) }
          def explode = Openapi30.raw(@node).key?("explode") ? !!@node.explode? : nil

          sig { override.returns(T::Boolean) }
          def allow_reserved? = !!@node.allow_reserved?

          sig { override.returns(T.nilable(Source::Schema)) }
          def schema = (node = @node.schema) && Schema.new(node)

          sig { override.returns(T.nilable(String)) }
          def description = @node.description

          sig { override.returns(T::Boolean) }
          def deprecated? = !!@node.deprecated?
        end

        class RequestBody
          extend T::Sig
          include Source::RequestBody

          sig { params(node: Openapi3Parser::Node::RequestBody).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, T.nilable(Source::Schema)]]) }
          def content = Openapi30.content(@node)

          sig { override.returns(T::Boolean) }
          def required? = !!@node.required?

          sig { override.returns(T.nilable(String)) }
          def description = @node.description
        end

        class Response
          extend T::Sig
          include Source::Response

          sig { params(node: Openapi3Parser::Node::Response).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, T.nilable(Source::Schema)]]) }
          def content = Openapi30.content(@node)

          sig { override.returns(T::Array[[String, Source::Header]]) }
          def headers = (@node.headers || []).map { |name, node| [name, Header.new(node)] }

          sig { override.returns(T.nilable(String)) }
          def description = @node.description
        end

        class Header
          extend T::Sig
          include Source::Header

          sig { params(node: Openapi3Parser::Node::Header).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(Source::Schema)) }
          def schema = (node = @node.schema) && Schema.new(node)

          sig { override.returns(T::Boolean) }
          def required? = !!@node.required?

          sig { override.returns(T.nilable(String)) }
          def description = @node.description
        end

        class SecurityScheme
          extend T::Sig
          include Source::SecurityScheme

          sig { params(node: Openapi3Parser::Node::SecurityScheme).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(String)) }
          def type = @node.type

          sig { override.returns(T.nilable(String)) }
          def name = @node.name

          sig { override.returns(T.nilable(String)) }
          def location = @node.in

          sig { override.returns(T.nilable(String)) }
          def scheme = @node.scheme

          sig { override.returns(T.nilable(String)) }
          def bearer_format = @node.bearer_format

          sig { override.returns(T::Array[T::Hash[String, String]]) }
          def flow_scopes
            flows = @node.flows
            return [] if flows.nil?

            OAUTH_FLOWS.filter_map do |flow_name|
              flow = T.let(flows.public_send(flow_name), T.nilable(Openapi3Parser::Node::OauthFlow))
              (flow.scopes || []).to_h { |scope, description| [scope.to_s, description.to_s] } if flow
            end
          end

          sig { override.returns(T.nilable(String)) }
          def open_id_connect_url = @node.open_id_connect_url

          sig { override.returns(T.nilable(String)) }
          def description = @node.description

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = Openapi30.extensions(@node)
        end

        class Schema
          extend T::Sig
          include Source::Schema

          sig { params(node: Openapi3Parser::Node::Schema).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(String)) }
          def name = @node.name

          sig { override.returns(String) }
          def key
            location = @node.node_context.source_location
            "#{location.source.source_input.path}#{location.pointer}"
          end

          sig { override.returns(T.nilable(String)) }
          def type = @node.type

          sig { override.returns(T::Boolean) }
          def nullable? = !!@node.nullable?

          sig { override.returns(T.nilable(String)) }
          def type_format = @node.format

          sig { override.returns(T.nilable(T::Array[T.untyped])) }
          def enum = @node.enum&.to_a

          sig { override.returns(T::Boolean) }
          def default? = Openapi30.raw(@node).key?("default")

          sig { override.returns(T.untyped) }
          def default = @node.default

          sig { override.returns(T.nilable(String)) }
          def description = @node.description

          sig { override.returns(T::Boolean) }
          def deprecated? = !!@node.deprecated?

          sig { override.returns(T::Boolean) }
          def read_only? = !!@node.read_only?

          sig { override.returns(T::Boolean) }
          def write_only? = !!@node.write_only?

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def all_of = @node.all_of&.map { |node| Schema.new(node) }

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def one_of = @node.one_of&.map { |node| Schema.new(node) }

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def any_of = @node.any_of&.map { |node| Schema.new(node) }

          sig { override.returns(T.nilable(Discriminator)) }
          def discriminator
            node = @node.discriminator
            return nil if node.nil?

            Discriminator.new(property_name: node.property_name,
                              mapping: node.mapping&.to_h { |value, ref| [value.to_s, ref.to_s] })
          end

          sig { override.returns(T.nilable(T::Array[[String, Source::Schema]])) }
          def properties = @node.properties&.map { |name, node| [name, Schema.new(node)] }

          sig { override.returns(T::Array[String]) }
          def required = @node.required.to_a.map(&:to_s)

          sig { override.returns(T.nilable(Source::Schema)) }
          def additional_properties = (node = @node.additional_properties_schema) && Schema.new(node)

          sig { override.returns(T.nilable(Source::Schema)) }
          def items = (node = @node.items) && Schema.new(node)

          sig { override.returns(T.nilable(Integer)) }
          def min_length = @node.min_length

          sig { override.returns(T.nilable(Integer)) }
          def max_length = @node.max_length

          sig { override.returns(T.nilable(String)) }
          def pattern = @node.pattern

          sig { override.returns(T.nilable(Numeric)) }
          def minimum = @node.minimum

          sig { override.returns(T.nilable(Numeric)) }
          def maximum = @node.maximum

          sig { override.returns(T::Boolean) }
          def exclusive_minimum? = !!@node.exclusive_minimum?

          sig { override.returns(T::Boolean) }
          def exclusive_maximum? = !!@node.exclusive_maximum?

          sig { override.returns(T.nilable(Numeric)) }
          def multiple_of = @node.multiple_of

          sig { override.returns(T.nilable(Integer)) }
          def min_items = @node.min_items

          sig { override.returns(T.nilable(Integer)) }
          def max_items = @node.max_items

          sig { override.returns(T::Boolean) }
          def unique_items? = !!@node.unique_items?

          sig { override.returns(T.nilable(Integer)) }
          def min_properties = @node.min_properties

          sig { override.returns(T.nilable(Integer)) }
          def max_properties = @node.max_properties

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = Openapi30.extensions(@node)
        end
      end
    end
  end
end
