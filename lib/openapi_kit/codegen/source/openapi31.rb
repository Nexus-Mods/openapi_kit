# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Source
      # OpenAPI 3.1 and 3.2, read from the document itself. Schemas are JSON Schema 2020-12:
      # null is a type, so a nullable schema lists "null" in `type` or has a `{type: "null"}`
      # member in `oneOf` or `anyOf`, and `$ref` may sit beside other keywords. 3.2 adds the
      # `query` operation. No Ruby library validates a 3.2 document, so this reader checks
      # the shape of each value it reads and raises SchemaError naming where it is.
      module Openapi31
        extend T::Sig

        VERBS = T.let(%w[get put post delete options head patch trace query].freeze, T::Array[String])
        OAUTH_FLOWS = T.let(%w[implicit password clientCredentials authorizationCode].freeze, T::Array[String])

        sig { params(path: Pathname, data: T::Hash[String, T.untyped]).returns(Source::Document) }
        def self.load(path, data)
          Document.new(Node.new(Reader.new(path, data), data, "#"))
        end

        # Resolves the document's local references. A reference to another file is refused
        # rather than followed.
        class Reader
          extend T::Sig

          sig { returns(Pathname) }
          attr_reader :path

          sig { params(path: Pathname, data: T::Hash[String, T.untyped]).void }
          def initialize(path, data)
            @path = path
            @data = data
          end

          sig { params(ref: T.untyped, from: String).returns([T::Hash[String, T.untyped], String]) }
          def resolve(ref, from)
            seen = T.let([], T::Array[String])
            current = T.let(ref, T.untyped)
            origin = T.let(from, String)
            loop do
              unless current.is_a?(String) && current.start_with?("#/")
                raise SchemaError,
                      "#{@path}#{origin}: $ref #{current.inspect} is not a reference into this document. " \
                      "openapi_kit follows only local references (#/...) in OpenAPI 3.1+ documents."
              end
              if seen.include?(current)
                raise SchemaError, "#{@path}#{origin}: $ref #{current} refers to itself through #{seen.join(" -> ")}."
              end

              seen << current
              target = lookup(current, origin)
              return [target, current] unless target.key?("$ref") && target.size == 1

              origin = current
              current = target["$ref"]
            end
          end

          private

          sig { params(ref: String, from: String).returns(T::Hash[String, T.untyped]) }
          def lookup(ref, from)
            segments = ref.delete_prefix("#/").split("/").map { |s| s.gsub("~1", "/").gsub("~0", "~") }
            target = segments.reduce(T.let(@data, T.untyped)) do |node, segment|
              case node
              when Hash then node[segment]
              when Array then node[segment.to_i] if segment.match?(/\A\d+\z/)
              end
            end
            return target if target.is_a?(Hash)

            raise SchemaError, "#{@path}#{from}: $ref #{ref} does not resolve to an object."
          end
        end

        # A JSON object in the document and the pointer it was read from. Accessors check the
        # type of what they read.
        class Node
          extend T::Sig

          sig { returns(Reader) }
          attr_reader :reader

          sig { returns(T::Hash[String, T.untyped]) }
          attr_reader :data

          sig { returns(String) }
          attr_reader :pointer

          sig { params(reader: Reader, data: T::Hash[String, T.untyped], pointer: String).void }
          def initialize(reader, data, pointer)
            @reader = reader
            @data = data
            @pointer = pointer
          end

          sig { params(key: String).returns(T::Boolean) }
          def key?(key) = @data.key?(key)

          sig { params(key: String).returns(T.untyped) }
          def [](key) = @data[key]

          sig { params(key: String).returns(T.nilable(String)) }
          def string(key) = typed(key, String, "a string")

          sig { params(key: String).returns(T::Boolean) }
          def boolean(key) = !!typed(key, T::Boolean, "true or false")

          sig { params(key: String).returns(T.nilable(Integer)) }
          def integer(key) = typed(key, Integer, "an integer")

          sig { params(key: String).returns(T.nilable(Numeric)) }
          def number(key) = typed(key, Numeric, "a number")

          sig { params(key: String).returns(T.nilable(T::Array[T.untyped])) }
          def array(key) = typed(key, T::Array[T.untyped], "an array")

          sig { params(key: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
          def object(key) = typed(key, T::Hash[T.untyped, T.untyped], "an object")

          # The object at `key`, following a reference. Fields an OpenAPI Reference Object may
          # carry beside `$ref` (summary and description) override the target's.
          sig { params(value: T.untyped, pointer: String).returns(Node) }
          def child(value, pointer)
            raise SchemaError, "#{where(pointer)} must be an object." unless value.is_a?(Hash)
            return Node.new(@reader, value, pointer) unless value.key?("$ref")

            target, ref = @reader.resolve(value["$ref"], pointer)
            Node.new(@reader, target.merge(value.slice("summary", "description")), ref)
          end

          # The object at `key`, or an empty one where the document leaves it out.
          sig { params(key: String).returns(Node) }
          def at(key)
            pointer = "#{@pointer}/#{key}"
            key?(key) ? child(@data[key], pointer) : Node.new(@reader, {}, pointer)
          end

          sig { params(key: String).returns(T::Array[[String, Node]]) }
          def children(key)
            (object(key) || {}).map do |name, value|
              [name.to_s, child(value, "#{@pointer}/#{key}/#{escape(name.to_s)}")]
            end
          end

          sig { params(key: String).returns(T::Array[Node]) }
          def items(key) = (array(key) || []).each_with_index.map { |value, i| child(value, "#{@pointer}/#{key}/#{i}") }

          sig { params(key: String).returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
          def requirements(key)
            array(key)&.each_with_index&.map do |requirement, i|
              raise SchemaError, "#{where("#{@pointer}/#{key}/#{i}")} must be an object." unless requirement.is_a?(Hash)

              requirement.to_h { |name, scopes| [name.to_s, Array(scopes).map(&:to_s)] }
            end
          end

          sig { returns(T::Hash[String, T.untyped]) }
          def extensions = @data.select { |k, _| k.to_s.start_with?("x-") }

          sig { params(pointer: String).returns(String) }
          def where(pointer = @pointer) = "#{@reader.path}#{pointer}"

          sig { params(name: String).returns(String) }
          def escape(name) = name.gsub("~", "~0").gsub("/", "~1")

          private

          sig { params(key: String, type: T.untyped, description: String).returns(T.untyped) }
          def typed(key, type, description)
            value = @data[key]
            return nil if value.nil?
            return value if T::Types::Base === type ? type.recursively_valid?(value) : value.is_a?(type) # rubocop:disable Style/CaseEquality

            raise SchemaError, "#{where}/#{escape(key)} must be #{description}, not #{value.inspect}."
          end
        end

        class Document
          extend T::Sig
          include Source::Document

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
            @info = T.let(node.at("info"), Node)
          end

          sig { override.returns(String) }
          def title = @info.string("title") || raise(SchemaError, "#{@info.where}/title is required.")

          sig { override.returns(String) }
          def version = @info.string("version") || raise(SchemaError, "#{@info.where}/version is required.")

          sig { override.returns(T::Array[[String, Source::PathItem]]) }
          def paths = @node.children("paths").map { |path, item| [path, PathItem.new(item)] }

          sig { override.returns(T::Array[[String, Source::Schema]]) }
          def schemas = @node.at("components").children("schemas").map { |name, node| [name, Schema.new(node)] }

          sig { override.returns(T::Array[[String, Source::SecurityScheme]]) }
          def security_schemes
            @node.at("components").children("securitySchemes").map { |name, node| [name, SecurityScheme.new(node)] }
          end

          sig { override.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
          def security = @node.requirements("security")
        end

        class PathItem
          extend T::Sig
          include Source::PathItem

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, Source::Operation]]) }
          def operations
            if @node.key?("additionalOperations")
              raise SchemaError,
                    "#{@node.where}/additionalOperations: openapi_kit routes only the methods OpenAPI names " \
                    "(#{VERBS.join(", ")})."
            end

            VERBS.filter_map do |verb|
              [verb, Operation.new(@node.child(@node[verb], "#{@node.pointer}/#{verb}"))] if @node.key?(verb)
            end
          end

          sig { override.returns(T::Array[Source::Parameter]) }
          def parameters = @node.items("parameters").map { |node| Parameter.new(node) }
        end

        class Operation
          extend T::Sig
          include Source::Operation

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(String)) }
          def operation_id = @node.string("operationId")

          sig { override.returns(T::Array[String]) }
          def tags = (@node.array("tags") || []).map(&:to_s)

          sig { override.returns(T::Array[Source::Parameter]) }
          def parameters = @node.items("parameters").map { |node| Parameter.new(node) }

          sig { override.returns(T.nilable(Source::RequestBody)) }
          def request_body
            RequestBody.new(@node.child(@node["requestBody"], "#{@node.pointer}/requestBody")) if
              @node.key?("requestBody")
          end

          sig { override.returns(T::Array[[String, Source::Response]]) }
          def responses
            node = @node.at("responses")
            node.data.keys.map do |status|
              [status.to_s, Response.new(node.child(node[status], "#{node.pointer}/#{status}"))]
            end
          end

          sig { override.returns(T.nilable(T::Array[T::Hash[String, T::Array[String]]])) }
          def security = @node.requirements("security")

          sig { override.returns(T.nilable(String)) }
          def summary = @node.string("summary")

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")

          sig { override.returns(T::Boolean) }
          def deprecated? = @node.boolean("deprecated")

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = @node.extensions
        end

        class Parameter
          extend T::Sig
          include Source::Parameter

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(String) }
          def name = @node.string("name") || raise(SchemaError, "#{@node.where}/name is required.")

          sig { override.returns(String) }
          def location = @node.string("in") || raise(SchemaError, "#{@node.where}/in is required.")

          sig { override.returns(T::Boolean) }
          def required? = @node.boolean("required")

          sig { override.returns(T.nilable(String)) }
          def style = @node.string("style")

          sig { override.returns(T.nilable(T::Boolean)) }
          def explode = @node.key?("explode") ? @node.boolean("explode") : nil

          sig { override.returns(T::Boolean) }
          def allow_reserved? = @node.boolean("allowReserved")

          sig { override.returns(T.nilable(Source::Schema)) }
          def schema = Openapi31.schema(@node, "schema")

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")

          sig { override.returns(T::Boolean) }
          def deprecated? = @node.boolean("deprecated")
        end

        class RequestBody
          extend T::Sig
          include Source::RequestBody

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, T.nilable(Source::Schema)]]) }
          def content = Openapi31.content(@node)

          sig { override.returns(T::Boolean) }
          def required? = @node.boolean("required")

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")
        end

        class Response
          extend T::Sig
          include Source::Response

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T::Array[[String, T.nilable(Source::Schema)]]) }
          def content = Openapi31.content(@node)

          sig { override.returns(T::Array[[String, Source::Header]]) }
          def headers = @node.children("headers").map { |name, node| [name, Header.new(node)] }

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")
        end

        class Header
          extend T::Sig
          include Source::Header

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(Source::Schema)) }
          def schema = Openapi31.schema(@node, "schema")

          sig { override.returns(T::Boolean) }
          def required? = @node.boolean("required")

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")
        end

        class SecurityScheme
          extend T::Sig
          include Source::SecurityScheme

          sig { params(node: Node).void }
          def initialize(node)
            @node = node
          end

          sig { override.returns(T.nilable(String)) }
          def type = @node.string("type")

          sig { override.returns(T.nilable(String)) }
          def name = @node.string("name")

          sig { override.returns(T.nilable(String)) }
          def location = @node.string("in")

          sig { override.returns(T.nilable(String)) }
          def scheme = @node.string("scheme")

          sig { override.returns(T.nilable(String)) }
          def bearer_format = @node.string("bearerFormat")

          sig { override.returns(T::Array[T::Hash[String, String]]) }
          def flow_scopes
            flows = @node.at("flows")
            OAUTH_FLOWS.select { |flow_name| flows.key?(flow_name) }.map do |flow_name|
              (flows.at(flow_name).object("scopes") || {}).to_h { |scope, description| [scope.to_s, description.to_s] }
            end
          end

          sig { override.returns(T.nilable(String)) }
          def open_id_connect_url = @node.string("openIdConnectUrl")

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = @node.extensions
        end

        sig { params(node: Node, key: String).returns(T.nilable(Source::Schema)) }
        def self.schema(node, key)
          Schema.read(node, node[key], "#{node.pointer}/#{key}") if node.key?(key)
        end

        sig { params(node: Node).returns(T::Array[[String, T.nilable(Source::Schema)]]) }
        def self.content(node)
          node.children("content").map { |media_type, media| [media_type, schema(media, "schema")] }
        end

        class Schema
          extend T::Sig
          include Source::Schema

          # Keywords whose meaning openapi_kit's types cannot carry, refused rather than dropped.
          UNSUPPORTED = T.let(
            {
              "prefixItems" => "a tuple has no Ruby type here; use items",
              "$dynamicRef" => "dynamic references are not followed"
            }.freeze,
            T::Hash[String, String]
          )

          # A schema at `pointer`. A `$ref` on its own is the schema it refers to. Beside other
          # keywords it applies alongside them, the way an allOf member does.
          sig { params(parent: Node, value: T.untyped, pointer: String).returns(Schema) }
          def self.read(parent, value, pointer)
            unless value.is_a?(Hash)
              raise SchemaError, "#{parent.where(pointer)} must be a schema object, not #{value.inspect}."
            end
            return new(Node.new(parent.reader, value, pointer)) unless value.key?("$ref")

            target, ref = parent.reader.resolve(value["$ref"], pointer)
            referenced = new(Node.new(parent.reader, target, ref))
            return referenced if value.size == 1

            new(Node.new(parent.reader, value.except("$ref"), pointer), referenced: referenced)
          end

          sig { params(node: Node, referenced: T.nilable(Schema)).void }
          def initialize(node, referenced: nil)
            @node = node
            @referenced = referenced
            reject_other_dialects!
            @types = T.let(declared_types, T::Array[String])
            @null_member = T.let(false, T::Boolean)
            @members = T.let(nil, T.nilable([T.nilable(T::Array[Source::Schema]), T.nilable(T::Array[Source::Schema])]))
          end

          sig { override.returns(T.nilable(String)) }
          def name
            segments = @node.pointer.split("/")
            segments[-1]&.gsub("~1", "/")&.gsub("~0", "~") if segments[-2] == "schemas" && @referenced.nil?
          end

          sig { override.returns(String) }
          def key = @node.where

          sig { override.returns(T.nilable(String)) }
          def type
            rest = @types - ["null"]
            return rest.first if rest.size <= 1

            raise SchemaError,
                  "#{@node.where}/type is #{@types.inspect}. openapi_kit types a schema as one type, " \
                  "optionally with \"null\"; use oneOf for a value that may be one of several types."
          end

          sig { override.returns(T::Boolean) }
          def nullable?
            members
            @types.include?("null") || @null_member || (@node.array("enum")&.include?(nil) || false)
          end

          sig { override.returns(T.nilable(String)) }
          def type_format = @node.string("format")

          sig { override.returns(T.nilable(T::Array[T.untyped])) }
          def enum = @node.array("enum")&.compact

          sig { override.returns(T::Boolean) }
          def default? = @node.key?("default")

          sig { override.returns(T.untyped) }
          def default = @node["default"]

          sig { override.returns(T.nilable(String)) }
          def description = @node.string("description")

          sig { override.returns(T::Boolean) }
          def deprecated? = @node.boolean("deprecated")

          sig { override.returns(T::Boolean) }
          def read_only? = @node.boolean("readOnly")

          sig { override.returns(T::Boolean) }
          def write_only? = @node.boolean("writeOnly")

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def all_of
            declared = schemas("allOf")
            collapsed = members[1]
            parts = [*(@referenced ? [@referenced] : []), *declared, *collapsed]
            parts.empty? && declared.nil? ? nil : parts
          end

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def one_of = (members[0] if @node.key?("oneOf"))

          sig { override.returns(T.nilable(T::Array[Source::Schema])) }
          def any_of = (members[0] if @node.key?("anyOf"))

          sig { override.returns(T.nilable(Discriminator)) }
          def discriminator
            return nil unless @node.key?("discriminator")

            node = @node.child(@node["discriminator"], "#{@node.pointer}/discriminator")
            property_name = node.string("propertyName") || raise(SchemaError, "#{node.where}/propertyName is required.")
            Discriminator.new(property_name: property_name,
                              mapping: node.object("mapping")&.to_h { |value, ref| [value.to_s, ref.to_s] })
          end

          sig { override.returns(T.nilable(T::Array[[String, Source::Schema]])) }
          def properties
            @node.object("properties")&.map do |name, value|
              [name.to_s, Schema.read(@node, value, "#{@node.pointer}/properties/#{@node.escape(name.to_s)}")]
            end
          end

          sig { override.returns(T::Array[String]) }
          def required = (@node.array("required") || []).map(&:to_s)

          sig { override.returns(T.nilable(Source::Schema)) }
          def additional_properties
            value = @node["additionalProperties"]
            Schema.read(@node, value, "#{@node.pointer}/additionalProperties") if value.is_a?(Hash)
          end

          sig { override.returns(T.nilable(Source::Schema)) }
          def items = Openapi31.schema(@node, "items")

          sig { override.returns(T.nilable(Integer)) }
          def min_length = @node.integer("minLength") || 0

          sig { override.returns(T.nilable(Integer)) }
          def max_length = @node.integer("maxLength")

          sig { override.returns(T.nilable(String)) }
          def pattern = @node.string("pattern")

          sig { override.returns(T.nilable(Numeric)) }
          def minimum = bound("minimum", "exclusiveMinimum", :>=).first

          sig { override.returns(T.nilable(Numeric)) }
          def maximum = bound("maximum", "exclusiveMaximum", :<=).first

          sig { override.returns(T::Boolean) }
          def exclusive_minimum? = bound("minimum", "exclusiveMinimum", :>=).last

          sig { override.returns(T::Boolean) }
          def exclusive_maximum? = bound("maximum", "exclusiveMaximum", :<=).last

          sig { override.returns(T.nilable(Numeric)) }
          def multiple_of = @node.number("multipleOf")

          sig { override.returns(T.nilable(Integer)) }
          def min_items = @node.integer("minItems") || 0

          sig { override.returns(T.nilable(Integer)) }
          def max_items = @node.integer("maxItems")

          sig { override.returns(T::Boolean) }
          def unique_items? = @node.boolean("uniqueItems")

          sig { override.returns(T.nilable(Integer)) }
          def min_properties = @node.integer("minProperties") || 0

          sig { override.returns(T.nilable(Integer)) }
          def max_properties = @node.integer("maxProperties")

          sig { override.returns(T::Hash[String, T.untyped]) }
          def extensions = @node.extensions

          private

          sig { void }
          def reject_other_dialects!
            if @node.key?("nullable")
              raise SchemaError,
                    "#{@node.where}/nullable is OpenAPI 3.0. In OpenAPI 3.1+ a nullable schema lists " \
                    "\"null\" in its type, as type: [string, \"null\"], or has a {type: \"null\"} member in oneOf."
            end
            %w[exclusiveMinimum exclusiveMaximum].each do |keyword|
              next unless [true, false].include?(@node[keyword])

              raise SchemaError,
                    "#{@node.where}/#{keyword} is a boolean, as in OpenAPI 3.0. In OpenAPI 3.1+ it is the bound itself."
            end
            UNSUPPORTED.each do |keyword, reason|
              raise SchemaError, "#{@node.where}/#{keyword}: #{reason}." if @node.key?(keyword)
            end
          end

          sig { returns(T::Array[String]) }
          def declared_types
            value = @node["type"]
            case value
            when nil then []
            when String then [value]
            when Array
              return value if value.all?(String)

              raise SchemaError, "#{@node.where}/type must be a string or an array of strings, not #{value.inspect}."
            else raise SchemaError, "#{@node.where}/type must be a string or an array of strings, not #{value.inspect}."
            end
          end

          # The oneOf or anyOf members besides a {type: "null"} one, which makes the schema
          # nullable. A single remaining member is the schema itself, so it applies as allOf does.
          sig { returns([T.nilable(T::Array[Source::Schema]), T.nilable(T::Array[Source::Schema])]) }
          def members
            @members ||= begin
              keyword = @node.key?("oneOf") ? "oneOf" : "anyOf"
              declared = schemas(keyword)
              rest = declared&.reject { |member| null_schema?(member) }
              @null_member = !declared.nil? && rest&.size != declared.size
              if @null_member && rest&.size == 1 && !@node.key?("discriminator")
                [nil, rest]
              else
                [rest, nil]
              end
            end
          end

          sig { params(schema: Schema).returns(T::Boolean) }
          def null_schema?(schema) = schema.null_only?

          sig { params(keyword: String).returns(T.nilable(T::Array[Schema])) }
          def schemas(keyword)
            @node.array(keyword)&.each_with_index&.map do |value, i|
              Schema.read(@node, value, "#{@node.pointer}/#{keyword}/#{i}")
            end
          end

          # The bound and whether it is exclusive. Where both are given, the tighter one holds.
          sig { params(inclusive: String, exclusive: String, tighter: Symbol).returns([T.nilable(Numeric), T::Boolean]) }
          def bound(inclusive, exclusive, tighter)
            plain = @node.number(inclusive)
            strict = @node.number(exclusive)
            return [plain, false] if strict.nil?
            return [strict, true] if plain.nil? || strict.public_send(tighter, plain)

            [plain, false]
          end

          protected

          sig { returns(T::Boolean) }
          def null_only? = @types == ["null"] && (@node.data.keys - %w[type title description]).empty?
        end
      end
    end
  end
end
