# typed: strict
# frozen_string_literal: true

require "openapi3_parser"

module Oapi
  module Codegen
    class Loader
      extend T::Sig

      VERBS = T.let(%w[get put post delete options head patch trace].freeze, T::Array[String])

      # The media types Rails parses into request_parameters and oapi renders as JSON.
      # Anything else would decode a Hash that was never there, so it is refused.
      DECODABLE_MEDIA_TYPES = T.let(
        %w[application/json application/x-www-form-urlencoded multipart/form-data].freeze,
        T::Array[String]
      )

      sig { params(config: Config).void }
      def initialize(config:)
        @config = config
        @types = T.let({}, T::Hash[String, Model::TypeDef])
        @keys_by_name = T.let({}, T::Hash[String, String])
        @in_progress = T.let(Set.new, T::Set[String])
      end

      sig { returns(Model::Document) }
      def parse
        document = Openapi3Parser.load_file(@config.spec)
        unless document.valid?
          details = document.errors.map { |e| "  #{e.context&.location_summary}: #{e.message}" }
          raise SchemaError, "#{@config.spec} is not a valid OpenAPI document:\n#{details.join("\n")}"
        end

        operations = build_operations(document)
        document.components&.schemas&.each { |name, node| schema_for(node, hint: name) }

        Model::Document.new(
          title: document.info.title,
          version: document.info.version,
          types: @types.values,
          operations: operations,
          security_schemes: build_security_schemes(document),
          security: requirements(document) || []
        )
      end

      private

      sig { params(document: Openapi3Parser::Document).returns(T::Array[Model::Operation]) }
      def build_operations(document)
        operations = document.paths.flat_map do |path, item|
          VERBS.filter_map do |verb|
            node = item.public_send(verb)
            node && build_operation(node, path: path, verb: verb, item: item)
          end
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
        operations
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
        params(node: Openapi3Parser::Node::Operation, path: String, verb: String,
               item: Openapi3Parser::Node::PathItem).returns(Model::Operation)
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
        own = node.parameters
        from_path_item = item.parameters
        declared = (own ? own.to_a : []) + (from_path_item ? from_path_item.to_a : [])
        parameters = declared.uniq { |p| [p.name, p.in] }
                             .map { |p| build_parameter(p, hint: base) }

        Model::Operation.new(
          id: id,
          http_method: Model::HttpMethod.deserialize(verb),
          path: path,
          tag: node.tags&.first || "default",
          parameters: parameters,
          request_body: body && build_request_body(body, hint: base),
          responses: build_responses(node, hint: base),
          security: requirements(node, declared: raw(node).key?("security")),
          summary: node.summary,
          description: node.description,
          deprecated: !!node.deprecated?,
          extensions: extensions(node)
        )
      end

      sig { params(node: Openapi3Parser::Node::Parameter, hint: String).returns(Model::Parameter) }
      def build_parameter(node, hint:)
        info = Model::ParameterInfo.new(
          name: node.name,
          identifier: Naming.identifier(node.name),
          schema: schema_for(node.schema, hint: "#{hint}#{Naming.pascal(node.name)}"),
          description: node.description,
          deprecated: !!node.deprecated?
        )
        explode = raw(node).key?("explode") ? !!node.explode? : nil

        case node.in
        when "path"
          Model::PathParameter.new(info: info, style: path_style(node), explode: explode || false)
        when "query"
          Model::QueryParameter.new(info: info, required: !!node.required?, style: query_style(node),
                                    explode: explode.nil? || explode,
                                    allow_reserved: !!node.allow_reserved?)
        when "header"
          Model::HeaderParameter.new(info: info, required: !!node.required?, explode: explode || false)
        when "cookie"
          Model::CookieParameter.new(info: info, required: !!node.required?,
                                     explode: explode.nil? || explode)
        else
          raise SchemaError, "Parameter #{node.name.inspect} has an unknown `in: #{node.in.inspect}`."
        end
      end

      sig { params(node: Openapi3Parser::Node::Parameter).returns(Model::PathStyle) }
      def path_style(node)
        return Model::PathStyle::Simple if node.style.nil?

        Model::PathStyle.try_deserialize(node.style) ||
          raise(SchemaError,
                "Path parameter #{node.name.inspect} has style #{node.style.inspect}. " \
                "Path parameters support simple, label or matrix.")
      end

      sig { params(node: Openapi3Parser::Node::Parameter).returns(Model::QueryStyle) }
      def query_style(node)
        return Model::QueryStyle::Form if node.style.nil?

        Model::QueryStyle.try_deserialize(node.style) ||
          raise(SchemaError,
                "Query parameter #{node.name.inspect} has style #{node.style.inspect}. " \
                "Query parameters support form, spaceDelimited, pipeDelimited or deepObject.")
      end

      sig { params(node: Openapi3Parser::Node::RequestBody, hint: String).returns(Model::RequestBody) }
      def build_request_body(node, hint:)
        Model::RequestBody.new(
          contents: contents(node, hint: "#{hint}Body", where: "the request body of #{hint}"),
          required: !!node.required?,
          description: node.description
        )
      end

      sig { params(node: Openapi3Parser::Node::Operation, hint: String).returns(T::Array[Model::Response]) }
      def build_responses(node, hint:)
        responses = node.responses
        return [] if responses.nil?

        responses.map do |raw_status, response|
          status = Model::Status.parse(raw_status.to_s)
          scoped = "#{hint}#{Model::Status.constant(status)}"
          Model::Response.new(
            status: status,
            contents: contents(
              response, hint: scoped, where: "the #{raw_status} response of #{hint}"
            ),
            headers: (response.headers || {}).map do |name, header|
              Model::Header.new(name: name, identifier: Naming.identifier(name),
                                schema: schema_for(header.schema, hint: "#{scoped}#{Naming.pascal(name)}"),
                                required: !!header.required?, description: header.description)
            end,
            description: response.description
          )
        end
      end

      sig do
        params(node: T.any(Openapi3Parser::Node::RequestBody, Openapi3Parser::Node::Response), hint: String,
               where: String).returns(T::Array[Model::Content])
      end
      def contents(node, hint:, where:)
        content = node.content
        return [] if content.nil?

        multiple = content.keys.size > 1
        content.map do |media_type, media|
          reject_undecodable_media_type!(media_type, where: where)
          suffix = multiple ? Naming.pascal(media_type.split("/").last.to_s.split("+").first.to_s) : ""
          Model::Content.new(media_type: media_type,
                             schema: (schema_for(media.schema, hint: "#{hint}#{suffix}") if media.schema))
        end
      end

      sig { params(media_type: String, where: String).void }
      def reject_undecodable_media_type!(media_type, where:)
        base = T.must(media_type.split(";").first).strip.downcase
        return if DECODABLE_MEDIA_TYPES.include?(base) || base.end_with?("+json")

        raise SchemaError,
              "#{where} declares the content type #{media_type}, which oapi cannot decode or " \
              "render. Supported content types are #{DECODABLE_MEDIA_TYPES.join(", ")} and any " \
              "+json media type."
      end

      sig { params(document: Openapi3Parser::Document).returns(T::Array[Model::SecurityScheme]) }
      def build_security_schemes(document)
        (document.components&.security_schemes || {}).map do |name, node|
          case node.type
          when "apiKey"
            Model::ApiKeyScheme.new(name: name, location: Model::ApiKeyLocation.deserialize(node.in),
                                    parameter_name: node.name, description: node.description)
          when "http"
            Model::HttpScheme.new(name: name, scheme: node.scheme.to_s.downcase,
                                  bearer_format: node.bearer_format, description: node.description)
          when "oauth2"
            Model::OAuth2Scheme.new(name: name, scopes: oauth_scopes(node), description: node.description)
          when "openIdConnect"
            Model::OpenIdConnectScheme.new(name: name, url: node.open_id_connect_url.to_s,
                                           description: node.description)
          else
            raise SchemaError, "Security scheme #{name.inspect} has unsupported type #{node.type.inspect}."
          end
        end
      end

      sig { params(node: Openapi3Parser::Node::SecurityScheme).returns(T::Hash[String, String]) }
      def oauth_scopes(node)
        flows = node.flows
        return {} if flows.nil?

        %i[implicit password client_credentials authorization_code].each_with_object({}) do |name, all|
          flow = flows.public_send(name)
          (flow&.scopes || {}).each { |scope, description| all[scope.to_s] = description.to_s }
        end
      end

      sig do
        params(node: T.any(Openapi3Parser::Document, Openapi3Parser::Node::Operation),
               declared: T::Boolean).returns(T.nilable(T::Array[Model::SecurityRequirement]))
      end
      def requirements(node, declared: true)
        security = node.security
        return nil if security.nil? || !declared

        security.map do |requirement|
          Model::SecurityRequirement.new(
            schemes: requirement.to_h.transform_values { |scopes| Array(scopes).map(&:to_s) }
          )
        end
      end

      sig do
        params(node: T.nilable(Openapi3Parser::Node::Schema), hint: String, nullable: T::Boolean,
               inherited: T.nilable(Model::Meta)).returns(Model::Schema)
      end
      def schema_for(node, hint:, nullable: false, inherited: nil)
        return Model::Untyped.new if node.nil?

        all_of = node.all_of
        members = all_of ? all_of.to_a : []
        properties = node.properties
        if members.size == 1 && (properties.nil? || properties.empty?)
          return schema_for(
            members.first,
            hint: hint,
            nullable: nullable || !!node.nullable?,
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

      sig { params(node: Openapi3Parser::Node::Schema).returns(T::Boolean) }
      def named_shape?(node)
        return true if node.enum || node.one_of || node.any_of || node.all_of&.any?

        properties = node.properties
        !(properties.nil? || properties.empty?)
      end

      sig { params(node: Openapi3Parser::Node::Schema, hint: String, meta: Model::Meta).returns(Model::Schema) }
      def structural(node, hint:, meta:)
        case node.type
        when "string"
          Model::StringSchema.new(format: node.format, min_length: node.min_length,
                                  max_length: node.max_length, pattern: node.pattern, meta: meta)
        when "integer"
          Model::IntegerSchema.new(format: node.format, minimum: node.minimum, maximum: node.maximum,
                                   exclusive_minimum: !!node.exclusive_minimum?,
                                   exclusive_maximum: !!node.exclusive_maximum?,
                                   multiple_of: node.multiple_of, meta: meta)
        when "number"
          Model::NumberSchema.new(format: node.format, minimum: node.minimum, maximum: node.maximum,
                                  exclusive_minimum: !!node.exclusive_minimum?,
                                  exclusive_maximum: !!node.exclusive_maximum?,
                                  multiple_of: node.multiple_of, meta: meta)
        when "boolean"
          Model::BooleanSchema.new(meta: meta)
        when "array"
          Model::List.new(items: schema_for(node.items, hint: "#{hint}Item"), min_items: node.min_items,
                          max_items: node.max_items, unique_items: !!node.unique_items?, meta: meta)
        when "object"
          values = node.additional_properties_schema
          Model::Freeform.new(values: (schema_for(values, hint: "#{hint}Value") if values),
                              min_properties: node.min_properties, max_properties: node.max_properties,
                              meta: meta)
        else
          Model::Untyped.new(meta: meta)
        end
      end

      sig { params(node: Openapi3Parser::Node::Schema, name: String).void }
      def register(node, name:)
        key = type_key(node)
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

      sig { params(node: Openapi3Parser::Node::Schema, name: String).returns(Model::TypeDef) }
      def build_type_def(node, name:)
        return enum_def(node, name: name) if node.enum
        return union_def(node, name: name) if node.one_of || node.any_of
        return object_def(node, name: name) if node.all_of&.any? || node.properties&.any?

        Model::AliasDef.new(name: name, target: structural(node, hint: name, meta: meta_for(node)),
                            meta: meta_for(node))
      end

      sig { params(node: Openapi3Parser::Node::Schema, name: String).returns(Model::TypeDef) }
      def enum_def(node, name:)
        values = node.enum.to_a
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

      sig { params(node: Openapi3Parser::Node::Schema, name: String).returns(Model::TypeDef) }
      def union_def(node, name:)
        declared = node.one_of || node.any_of
        raw = declared ? declared.to_a : []
        members = raw.each_with_index.map { |m, i| schema_for(m, hint: "#{name}Member#{i + 1}") }

        Model::UnionDef.new(name: name, members: members, tag: union_tag(node),
                            meta: meta_for(node))
      end

      sig { params(node: Openapi3Parser::Node::Schema, name: String).returns(Model::TypeDef) }
      def object_def(node, name:)
        properties = T.let({}, T::Hash[String, Openapi3Parser::Node::Schema])
        required = T.let(Set.new, T::Set[String])
        collect_properties(node, properties, required)

        Model::ObjectDef.new(
          name: name,
          properties: properties.map do |pname, pnode|
            Model::Property.new(name: pname, identifier: Naming.identifier(pname),
                                schema: schema_for(pnode, hint: "#{name}#{Naming.pascal(pname)}"),
                                required: required.include?(pname))
          end,
          additional_properties: additional_properties_for(node, name),
          meta: meta_for(node)
        )
      end

      sig { params(node: Openapi3Parser::Node::Schema, name: String).returns(T.nilable(Model::Schema)) }
      def additional_properties_for(node, name)
        schema = node.additional_properties_schema
        return nil if schema.nil?

        schema_for(schema, hint: "#{name}Value")
      end

      sig do
        params(node: Openapi3Parser::Node::Schema, properties: T::Hash[String, Openapi3Parser::Node::Schema],
               required: T::Set[String]).void
      end
      def collect_properties(node, properties, required)
        all_of = node.all_of
        all_of&.each { |member| collect_properties(member, properties, required) }
        (node.properties || {}).each { |pname, pnode| properties[pname] = pnode }
        node.required&.each { |name| required << name.to_s }
      end

      sig { params(node: Openapi3Parser::Node::Schema).returns(Model::UnionTag) }
      def union_tag(node)
        discriminator = node.discriminator
        return Model::Untagged.new if discriminator.nil?

        declared = discriminator.mapping
        mapping = declared ? declared.to_h { |value, ref| [value.to_s, rename(ref.to_s.split("/").last.to_s)] } : {}
        mapping = implicit_mapping(node) if mapping.empty?

        Model::Tagged.new(property_name: discriminator.property_name, mapping: mapping)
      end

      sig { params(node: Openapi3Parser::Node::Schema).returns(T::Hash[String, String]) }
      def implicit_mapping(node)
        declared = node.one_of || node.any_of
        members = declared ? declared.to_a : []
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

      sig { params(node: Openapi3Parser::Node::Schema, nullable: T::Boolean).returns(Model::Meta) }
      def meta_for(node, nullable: false)
        data = raw(node)
        Model::Meta.new(
          description: node.description,
          nullable: nullable || !!node.nullable?,
          deprecated: !!node.deprecated?,
          default: data.key?("default") ? Model::Default.new(value: node.default) : nil,
          read_only: !!node.read_only?,
          write_only: !!node.write_only?,
          extensions: extensions(node),
          ruby_type: ruby_type_for(data)
        )
      end

      sig { params(node: Openapi3Parser::Node::Schema).returns(String) }
      def type_key(node)
        location = node.node_context.source_location
        "#{location.source.source_input.path}#{location.pointer}"
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
                "instance of a class including, Oapi::Codec."
        end

        RubyType.new(type: type.to_s, codec: codec.to_s)
      end

      sig { params(name: String).returns(String) }
      def rename(name) = Naming.constant(@config.name_overrides.fetch(name, name))

      sig { params(node: Openapi3Parser::Node::Object).returns(T::Hash[String, T.untyped]) }
      def extensions(node)
        raw(node).select { |k, _| k.to_s.start_with?("x-") }
      end

      sig { params(node: Openapi3Parser::Node::Object).returns(T::Hash[String, T.untyped]) }
      def raw(node)
        input = node.node_context.input
        input.is_a?(Hash) ? input : {}
      end
    end
  end
end
