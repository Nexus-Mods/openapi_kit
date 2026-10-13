# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    class Loader
      extend T::Sig

      MULTIPART_SHAPE = T.let(
        "A multipart body must be an object whose properties are the fields it accepts.",
        String
      )

      # The media types Rails parses into request_parameters and openapi_kit renders as JSON.
      # Anything else would decode a Hash that was never there, so it is refused.
      DECODABLE_MEDIA_TYPES = T.let(
        %w[application/json application/x-www-form-urlencoded multipart/form-data].freeze,
        T::Array[String]
      )

      sig { returns(T::Array[String]) }
      def warnings = @warnings.to_a

      sig { params(config: Config).void }
      def initialize(config:)
        @config = config
        @warnings = T.let(Set.new, T::Set[String])
        @types = T.let({}, T::Hash[String, Model::TypeDef])
        @keys_by_name = T.let({}, T::Hash[String, String])
        @in_progress = T.let(Set.new, T::Set[String])
      end

      sig { returns(Model::Document) }
      def parse
        document = Source.load(@config.spec)

        operations = build_operations(document)
        document.schemas.each { |name, node| schema_for(node, hint: name) }

        security = requirements(document.security) || []
        reject_untypeable_security!(operations, security)

        Model::Document.new(
          title: document.title,
          version: document.version,
          types: @types.values,
          operations: operations,
          security_schemes: build_security_schemes(document),
          security: security
        )
      end

      private

      sig { params(document: Source::Document).returns(T::Array[Model::Operation]) }
      def build_operations(document)
        operations = document.paths.flat_map do |path, item|
          item.operations.map { |verb, node| build_operation(node, path: path, verb: verb, item: item) }
        end

        reject_collisions!(
          operations.map(&:id),
          subject: "operationIds",
          consequence: "each operation needs its own handler method, types and route"
        )
        reject_collisions!(
          operations.map(&:tag),
          subject: "tags",
          consequence: "each tag needs its own handler interface and controller"
        )
        operations.each { |operation| reject_misplaced_binary!(operation) }
        operations
      end

      sig { params(operation: Model::Operation).void }
      def reject_misplaced_binary!(operation)
        operation.parameters.each do |parameter|
          info = Model::Parameter.info(parameter)
          reject_binary_within!(info.schema, "parameter #{info.name.inspect} of #{operation.id}")
        end

        operation.request_body&.contents&.each { |content| reject_binary_in_request!(content, operation) }
        operation.responses.each { |response| reject_binary_in_response!(response, operation) }
      end

      sig { params(content: Model::Content, operation: Model::Operation).void }
      def reject_binary_in_request!(content, operation)
        schema = content.schema
        return if schema.nil?

        where = "the request body of #{operation.id}"
        return reject_binary_within!(schema, where) unless content.multipart?

        reject_binary!(schema, where)
        form_fields(schema).each do |property|
          next if Model::Schema.file?(property.schema)

          reject_binary_within!(property.schema, "#{property.name.inspect} in #{where}")
        end
      end

      sig { params(response: Model::Response, operation: Model::Operation).void }
      def reject_binary_in_response!(response, operation)
        where = "the #{Model::Status.constant(response.status)} response of #{operation.id}"

        response.headers.each do |header|
          reject_binary_within!(header.schema, "header #{header.name.inspect} of #{where}")
        end

        response.contents.each do |content|
          schema = content.schema
          next if schema.nil? || Model::Schema.file?(schema)

          reject_binary_within!(schema, where)
        end
      end

      sig { params(schema: Model::Schema, where: String, seen: T::Set[String]).void }
      def reject_binary_within!(schema, where, seen = Set.new)
        case schema
        when Model::StringSchema then reject_binary!(schema, where)
        when Model::Ref then reject_binary_in_type!(schema.name, where, seen)
        when Model::List then reject_binary_within!(schema.items, where, seen)
        when Model::Freeform
          values = schema.values
          reject_binary_within!(values, where, seen) unless values.nil?
        end
      end

      sig { params(name: String, where: String, seen: T::Set[String]).void }
      def reject_binary_in_type!(name, where, seen)
        return unless seen.add?(name)

        case (type = type_named(name))
        when Model::ObjectDef, Model::FormDef
          type.properties.each { |property| reject_binary_within!(property.schema, where, seen) }
          extra = type.additional_properties
          reject_binary_within!(extra, where, seen) unless extra.nil?
        when Model::UnionDef then type.members.each { |member| reject_binary_within!(member, where, seen) }
        when Model::AliasDef then reject_binary_within!(type.target, where, seen)
        when Model::EnumDef, nil then nil
        else T.absurd(type)
        end
      end

      sig { params(schema: Model::Schema, where: String).void }
      def reject_binary!(schema, where)
        return unless Model::Schema.file?(schema)

        raise SchemaError,
              "#{where} declares format: binary, which cannot be produced there. It is only " \
              "valid as a top-level property of a multipart/form-data request body, or as the " \
              "whole schema of a response body. Use format: byte to carry bytes inside JSON, " \
              "or x-ruby-type to name a type of your own."
      end

      sig { params(schema: Model::Schema).returns(T::Array[Model::Property]) }
      def form_fields(schema)
        return [] unless schema.is_a?(Model::Ref)

        case (type = type_named(schema.name))
        when Model::ObjectDef, Model::FormDef then type.properties
        else []
        end
      end

      sig { params(name: String).returns(T.nilable(Model::TypeDef)) }
      def type_named(name)
        key = @keys_by_name[name]
        key && @types[key]
      end

      # With principals configured, openapi_kit resolves the alternatives itself, so it has to be
      # able to name the type each one produces.
      sig do
        params(operations: T::Array[Model::Operation],
               fallback: T::Array[Model::SecurityRequirement]).void
      end
      def reject_untypeable_security!(operations, fallback)
        operations.each do |operation|
          (operation.security || fallback).each do |requirement|
            reject_untypeable_requirement!(operation, requirement)
          end
        end
      end

      sig { params(operation: Model::Operation, requirement: Model::SecurityRequirement).void }
      def reject_untypeable_requirement!(operation, requirement)
        if requirement.schemes.size > 1
          raise SchemaError,
                "#{operation.id} requires #{requirement.schemes.keys.join(" and ")} together. " \
                "openapi_kit cannot yet name the type that produces: give the operation one scheme per " \
                "alternative, or drop `principals` and authenticate in your base controller."
        end

        return unless @config.principal.nil?

        raise ConfigError,
              "#{operation.id} declares security, so a successful authentication produces a " \
              "principal, but no `principal` is configured. Name the class it produces, " \
              "e.g. principal: \"MyApp::Principal\"."
      end

      sig { params(names: T::Array[String], subject: String, consequence: String).void }
      def reject_collisions!(names, subject:, consequence:)
        names.uniq.group_by { |name| Naming.snake(name) }.each do |normalised, originals|
          next if originals.size == 1

          raise SchemaError,
                "#{subject} #{originals.sort.join(", ")} all generate the name #{normalised}. " \
                "Rename all but one: #{consequence}."
        end
      end

      sig do
        params(node: Source::Operation, path: String, verb: String,
               item: Source::PathItem).returns(Model::Operation)
      end
      def build_operation(node, path:, verb:, item:)
        id = node.operation_id
        if id.nil? || id.to_s.empty?
          raise SchemaError,
                "#{verb.upcase} #{path} has no operationId. Every operation needs one: it names " \
                "the handler method, the request and response types, and the route."
        end

        base = Naming.pascal(id)
        body = node.request_body
        declared = node.parameters + item.parameters
        parameters = declared.uniq { |p| [p.name, p.location] }
                             .map { |p| build_parameter(p, hint: base) }

        Model::Operation.new(
          id: id,
          http_method: Model::HttpMethod.deserialize(verb),
          path: path,
          tag: node.tags.first || "default",
          parameters: parameters,
          request_body: (build_request_body(body, hint: base) if body),
          responses: build_responses(node, hint: base),
          security: requirements(node.security),
          summary: node.summary,
          description: node.description,
          deprecated: !!node.deprecated?,
          extensions: node.extensions
        )
      end

      sig { params(node: Source::Parameter, hint: String).returns(Model::Parameter) }
      def build_parameter(node, hint:)
        info = Model::ParameterInfo.new(
          name: node.name,
          identifier: Naming.identifier(node.name),
          schema: schema_for(node.schema, hint: "#{hint}#{Naming.pascal(node.name)}"),
          description: node.description,
          deprecated: node.deprecated?
        )
        explode = node.explode

        case node.location
        when "path"
          Model::PathParameter.new(info: info, style: path_style(node), explode: explode || false)
        when "query"
          Model::QueryParameter.new(info: info, required: node.required?, style: query_style(node),
                                    explode: explode.nil? || explode,
                                    allow_reserved: node.allow_reserved?)
        when "header"
          Model::HeaderParameter.new(info: info, required: node.required?, explode: explode || false)
        when "cookie"
          Model::CookieParameter.new(info: info, required: node.required?,
                                     explode: explode.nil? || explode)
        else
          raise SchemaError, "Parameter #{node.name.inspect} has an unknown `in: #{node.location.inspect}`."
        end
      end

      sig { params(node: Source::Parameter).returns(Model::PathStyle) }
      def path_style(node)
        return Model::PathStyle::Simple if node.style.nil?

        Model::PathStyle.try_deserialize(node.style) ||
          raise(SchemaError,
                "Path parameter #{node.name.inspect} has style #{node.style.inspect}. " \
                "Path parameters support simple, label or matrix.")
      end

      sig { params(node: Source::Parameter).returns(Model::QueryStyle) }
      def query_style(node)
        return Model::QueryStyle::Form if node.style.nil?

        Model::QueryStyle.try_deserialize(node.style) ||
          raise(SchemaError,
                "Query parameter #{node.name.inspect} has style #{node.style.inspect}. " \
                "Query parameters support form, spaceDelimited, pipeDelimited or deepObject.")
      end

      sig { params(node: Source::RequestBody, hint: String).returns(Model::RequestBody) }
      def build_request_body(node, hint:)
        Model::RequestBody.new(
          contents: contents(node.content, hint: "#{hint}Body", where: "the request body of #{hint}",
                                           request: true),
          required: node.required?,
          description: node.description
        )
      end

      sig { params(node: Source::Operation, hint: String).returns(T::Array[Model::Response]) }
      def build_responses(node, hint:)
        node.responses.map do |raw_status, response|
          status = Model::Status.parse(raw_status)
          scoped = "#{hint}#{Model::Status.constant(status)}"
          Model::Response.new(
            status: status,
            contents: contents(
              response.content, hint: scoped, where: "the #{raw_status} response of #{hint}"
            ),
            headers: response.headers.map do |name, header|
              Model::Header.new(name: name, identifier: Naming.identifier(name),
                                schema: schema_for(header.schema, hint: "#{scoped}#{Naming.pascal(name)}"),
                                required: header.required?, description: header.description)
            end,
            description: response.description
          )
        end
      end

      sig do
        params(content: T::Array[[String, T.nilable(Source::Schema)]], hint: String,
               where: String, request: T::Boolean).returns(T::Array[Model::Content])
      end
      def contents(content, hint:, where:, request: false)
        multiple = content.size > 1
        content.map do |media_type, declared|
          suffix = multiple ? Naming.pascal(media_type.split("/").last.to_s.split("+").first.to_s) : ""
          schema = (schema_for(declared, hint: "#{hint}#{suffix}") if declared)
          reject_undecodable_media_type!(media_type, where: where, schema: schema)
          reject_unspreadable_multipart!(schema: schema, where: where) if
            request && Model::Content.multipart?(media_type)
          Model::Content.new(media_type: media_type, schema: schema)
        end
      end

      sig { params(schema: T.nilable(Model::Schema), where: String).void }
      def reject_unspreadable_multipart!(schema:, where:)
        raise SchemaError, "#{multipart_prefix(where)} declares no schema. #{MULTIPART_SHAPE}" if schema.nil?

        type = schema.is_a?(Model::Ref) ? type_named(schema.name) : nil
        return if type.is_a?(Model::ObjectDef) || type.is_a?(Model::FormDef)

        raise SchemaError, "#{multipart_prefix(where)} is not an object. #{MULTIPART_SHAPE}"
      end

      sig { params(where: String).returns(String) }
      def multipart_prefix(where) = "The multipart/form-data content of #{where}"

      sig { params(media_type: String, where: String, schema: T.nilable(Model::Schema)).void }
      def reject_undecodable_media_type!(media_type, where:, schema:)
        base = T.must(media_type.split(";").first).strip.downcase
        return if DECODABLE_MEDIA_TYPES.include?(base) || base.end_with?("+json")
        return if !schema.nil? && Model::Schema.file?(schema)

        raise SchemaError,
              "#{where} declares the content type #{media_type}, which openapi_kit cannot decode or " \
              "render. Supported content types are #{DECODABLE_MEDIA_TYPES.join(", ")}, any " \
              "+json media type, and any type at all for a response body whose schema is " \
              "format: binary."
      end

      sig { params(document: Source::Document).returns(T::Array[Model::SecurityScheme]) }
      def build_security_schemes(document)
        document.security_schemes.map do |name, node|
          case node.type
          when "apiKey"
            Model::ApiKeyScheme.new(name: name, location: Model::ApiKeyLocation.deserialize(node.location),
                                    parameter_name: T.must(node.name), description: node.description,
                                    extensions: node.extensions)
          when "http"
            Model::HttpScheme.new(name: name, scheme: node.scheme.to_s.downcase,
                                  bearer_format: node.bearer_format, description: node.description,
                                  extensions: node.extensions)
          when "oauth2"
            Model::OAuth2Scheme.new(name: name, scopes: oauth_scopes(node, name: name), description: node.description,
                                    extensions: node.extensions)
          when "openIdConnect"
            Model::OpenIDConnectScheme.new(name: name, url: node.open_id_connect_url.to_s,
                                           description: node.description, extensions: node.extensions)
          else
            raise SchemaError, "Security scheme #{name.inspect} has unsupported type #{node.type.inspect}."
          end
        end
      end

      sig do
        params(node: Source::SecurityScheme, name: String)
          .returns(T::Hash[String, String])
      end
      # A server checks scope names and nothing else: the flows' authorizationUrl,
      # tokenUrl and refreshUrl tell a client where to get a token, so they are not
      # carried. Scopes are unioned across the flows, and a scope described two ways
      # warns rather than losing one description quietly.
      def oauth_scopes(node, name:)
        node.flow_scopes.each_with_object({}) do |scopes, all|
          scopes.each do |scope, description|
            warn_scope_conflict(name, scope, all[scope], description)
            all[scope] = description
          end
        end
      end

      sig do
        params(scheme: String, scope: String, existing: T.nilable(String), description: String).void
      end
      def warn_scope_conflict(scheme, scope, existing, description)
        return if existing.nil? || existing == description

        @warnings << "The scope #{scope.inspect} of security scheme #{scheme.inspect} is " \
                     "described two ways across its OAuth flows: #{existing.inspect} and " \
                     "#{description.inspect}. openapi_kit keeps the last."
      end

      sig do
        params(security: T.nilable(T::Array[T::Hash[String, T::Array[String]]]))
          .returns(T.nilable(T::Array[Model::SecurityRequirement]))
      end
      def requirements(security)
        security&.map { |schemes| Model::SecurityRequirement.new(schemes: schemes) }
      end

      sig do
        params(node: T.nilable(Source::Schema), hint: String, nullable: T::Boolean,
               inherited: T.nilable(Model::Meta)).returns(Model::Schema)
      end
      def schema_for(node, hint:, nullable: false, inherited: nil)
        return Model::Untyped.new if node.nil?

        members = node.all_of || []
        properties = node.properties
        if members.size == 1 && (properties.nil? || properties.empty?)
          return schema_for(
            members.first,
            hint: hint,
            nullable: nullable || node.nullable?,
            inherited: merge_meta(inherited, meta_for(node, nullable: nullable))
          )
        end

        meta = merge_meta(inherited, meta_for(node, nullable: nullable))
        declared = node.name
        name =
          if declared
            rename(declared)
          elsif named_shape?(node)
            rename(hint)
          end
        if name
          register(node, name: name)
          return Model::Ref.new(name: name, meta: meta)
        end

        structural(node, hint: hint, meta: meta)
      end

      sig { params(over: T.nilable(Model::Meta), under: Model::Meta).returns(Model::Meta) }
      def merge_meta(over, under)
        return under if over.nil?

        Model::Meta.new(
          description: over.description || under.description,
          nullable: over.nullable || under.nullable,
          deprecated: over.deprecated || under.deprecated,
          default: over.default || under.default,
          read_only: over.read_only || under.read_only,
          write_only: over.write_only || under.write_only,
          extensions: under.extensions.merge(over.extensions),
          ruby_type: over.ruby_type || under.ruby_type
        )
      end

      sig { params(node: Source::Schema).returns(T::Boolean) }
      def named_shape?(node)
        return true if node.enum || node.one_of || node.any_of || node.all_of&.any?

        properties = node.properties
        !(properties.nil? || properties.empty?)
      end

      sig { params(node: Source::Schema, hint: String, meta: Model::Meta).returns(Model::Schema) }
      def structural(node, hint:, meta:)
        case node.type
        when "string"
          Model::StringSchema.new(format: node.type_format, min_length: node.min_length,
                                  max_length: node.max_length, pattern: node.pattern, meta: meta)
        when "integer"
          Model::IntegerSchema.new(format: node.type_format,
                                   minimum: T.cast(node.minimum, T.nilable(Integer)),
                                   maximum: T.cast(node.maximum, T.nilable(Integer)),
                                   exclusive_minimum: node.exclusive_minimum?,
                                   exclusive_maximum: node.exclusive_maximum?,
                                   multiple_of: node.multiple_of, meta: meta)
        when "number"
          Model::NumberSchema.new(format: node.type_format, minimum: node.minimum, maximum: node.maximum,
                                  exclusive_minimum: node.exclusive_minimum?,
                                  exclusive_maximum: node.exclusive_maximum?,
                                  multiple_of: node.multiple_of, meta: meta)
        when "boolean"
          Model::BooleanSchema.new(meta: meta)
        when "array"
          Model::List.new(items: schema_for(node.items, hint: "#{hint}Item"), min_items: node.min_items,
                          max_items: node.max_items, unique_items: node.unique_items?, meta: meta)
        when "object"
          values = node.additional_properties
          Model::Freeform.new(values: (schema_for(values, hint: "#{hint}Value") if values),
                              min_properties: node.min_properties, max_properties: node.max_properties,
                              meta: meta)
        else
          Model::Untyped.new(meta: meta)
        end
      end

      sig { params(node: Source::Schema, name: String).void }
      def register(node, name:)
        key = node.key
        existing = @keys_by_name[name]
        if existing && existing != key
          raise SchemaError,
                "Two different schemas both generate the name #{name}:\n  #{existing}\n  #{key}\n" \
                "Disambiguate with name_overrides in your config."
        end
        return if @types.key?(key) || @in_progress.include?(key)

        @in_progress << key
        @keys_by_name[name] = key
        begin
          @types[key] = build_type_def(node, name: name)
        ensure
          @in_progress.delete(key)
        end
      end

      sig { params(node: Source::Schema, name: String).returns(Model::TypeDef) }
      def build_type_def(node, name:)
        return enum_def(node, name: name) if node.enum
        return union_def(node, name: name) if node.one_of || node.any_of
        return object_def(node, name: name) if node.all_of&.any? || node.properties&.any?

        Model::AliasDef.new(name: name, target: structural(node, hint: name, meta: meta_for(node)),
                            meta: meta_for(node))
      end

      sig { params(node: Source::Schema, name: String).returns(Model::TypeDef) }
      def enum_def(node, name:)
        values = node.enum || []
        kinds = values.map(&:class).uniq

        unless [[String], [Integer]].include?(kinds)
          raise SchemaError,
                "Enum #{name} has values of type #{kinds.map(&:name).sort.join(", ")}. " \
                "A T::Enum needs its values to be all strings or all integers."
        end

        Model::EnumDef.new(
          name: name,
          members: values.map { |v| Model::EnumMember.new(constant: Naming.enum_member(v), value: v) },
          meta: meta_for(node)
        )
      end

      sig { params(node: Source::Schema, name: String).returns(Model::TypeDef) }
      def union_def(node, name:)
        declared = node.one_of || node.any_of || []
        members = declared.each_with_index.map { |m, i| schema_for(m, hint: "#{name}Member#{i + 1}") }

        Model::UnionDef.new(name: name, members: members, tag: union_tag(node),
                            meta: meta_for(node))
      end

      sig { params(node: Source::Schema, name: String).returns(Model::TypeDef) }
      def object_def(node, name:)
        properties = T.let({}, T::Hash[String, Source::Schema])
        required = T.let(Set.new, T::Set[String])
        collect_properties(node, properties, required)

        fields = properties.map do |pname, pnode|
          Model::Property.new(name: pname, identifier: Naming.identifier(pname),
                              schema: schema_for(pnode, hint: "#{name}#{Naming.pascal(pname)}"),
                              required: required.include?(pname))
        end
        kind = fields.any? { |field| Model::Schema.file?(field.schema) } ? Model::FormDef : Model::ObjectDef

        kind.new(name: name, properties: fields,
                 additional_properties: additional_properties_for(node, name),
                 meta: meta_for(node))
      end

      sig { params(node: Source::Schema, name: String).returns(T.nilable(Model::Schema)) }
      def additional_properties_for(node, name)
        schema = node.additional_properties
        return nil if schema.nil?

        schema_for(schema, hint: "#{name}Value")
      end

      sig do
        params(node: Source::Schema, properties: T::Hash[String, Source::Schema],
               required: T::Set[String]).void
      end
      def collect_properties(node, properties, required)
        node.all_of&.each { |member| collect_properties(member, properties, required) }
        node.properties&.each { |pname, pnode| properties[pname] = pnode }
        node.required.each { |name| required << name }
      end

      sig { params(node: Source::Schema).returns(Model::UnionTag) }
      def union_tag(node)
        discriminator = node.discriminator
        return Model::Untagged.new if discriminator.nil?

        declared = discriminator.mapping
        mapping = declared ? declared.transform_values { |ref| rename(ref.split("/").last.to_s) } : {}
        mapping = implicit_mapping(node) if mapping.empty?

        Model::Tagged.new(property_name: discriminator.property_name, mapping: mapping)
      end

      sig { params(node: Source::Schema).returns(T::Hash[String, String]) }
      def implicit_mapping(node)
        members = node.one_of || node.any_of || []
        members.to_h do |member|
          name = member.name
          if name.nil?
            raise SchemaError,
                  "A member of the discriminated union #{node.name || "(inline)"} is an inline " \
                  "schema, so there is no name to map a discriminator value to. Move it into " \
                  "components/schemas, or declare an explicit discriminator mapping."
          end

          [name, rename(name)]
        end
      end

      sig { params(node: Source::Schema, nullable: T::Boolean).returns(Model::Meta) }
      def meta_for(node, nullable: false)
        extensions = node.extensions
        Model::Meta.new(
          description: node.description,
          nullable: nullable || node.nullable?,
          deprecated: node.deprecated?,
          default: node.default? ? Model::Default.new(value: node.default) : nil,
          read_only: node.read_only?,
          write_only: node.write_only?,
          extensions: extensions,
          ruby_type: ruby_type_for(extensions)
        )
      end

      sig { params(data: T::Hash[String, T.untyped]).returns(T.nilable(RubyType)) }
      def ruby_type_for(data)
        type = data["x-ruby-type"]
        codec = data["x-ruby-codec"]
        return nil if type.nil? && codec.nil?

        if type.nil? || codec.nil?
          raise SchemaError,
                "x-ruby-type and x-ruby-codec must be given together (found only " \
                "#{type.nil? ? "x-ruby-codec" : "x-ruby-type"}). `x-ruby-type` is what appears in " \
                "signatures, `x-ruby-codec` is what converts it: a module extending, or an " \
                "instance of a class including, OpenAPIKit::Codec."
        end

        RubyType.new(type: type.to_s, codec: codec.to_s)
      end

      sig { params(name: String).returns(String) }
      def rename(name) = Naming.constant(@config.name_overrides.fetch(name, name))
    end
  end
end
