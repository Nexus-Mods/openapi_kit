# typed: strict
# frozen_string_literal: true

require "openapi3_parser"

module Oapi
  class Loader
    extend T::Sig

    VERBS = T.let(%w[get put post delete options head patch trace].freeze, T::Array[String])

    sig { params(config: Config).void }
    def initialize(config:)
      @config = config
      @types = T.let({}, T::Hash[String, Ir::TypeDef])
      @keys_by_name = T.let({}, T::Hash[String, String])
      @in_progress = T.let(Set.new, T::Set[String])
    end

    sig { returns(Ir::Document) }
    def parse
      document = Openapi3Parser.load_file(@config.spec)
      unless document.valid?
        details = document.errors.map { |e| "  #{e.context&.location_summary}: #{e.message}" }
        raise SchemaError, "#{@config.spec} is not a valid OpenAPI document:\n#{details.join("\n")}"
      end

      operations = build_operations(document)
      document.components&.schemas&.each { |name, node| schema_for(node, hint: name) }

      Ir::Document.new(
        title: document.info.title,
        version: document.info.version,
        types: @types.values,
        operations: operations,
        security_schemes: build_security_schemes(document),
        security: requirements(document.security) || []
      )
    end

    private

    sig { params(document: T.untyped).returns(T::Array[Ir::Operation]) }
    def build_operations(document)
      document.paths.flat_map do |path, item|
        VERBS.filter_map do |verb|
          node = item.public_send(verb)
          node && build_operation(node, path: path, verb: verb, item: item)
        end
      end
    end

    sig { params(node: T.untyped, path: String, verb: String, item: T.untyped).returns(Ir::Operation) }
    def build_operation(node, path:, verb:, item:)
      id = node.operation_id
      if id.nil? || id.to_s.empty?
        raise SchemaError,
              "#{verb.upcase} #{path} has no operationId. Every operation needs one: it names " \
              "the handler method, the request and response types, and the route."
      end

      base = Naming.pascal(id)
      parameters = (Array(item.parameters) + Array(node.parameters))
                   .uniq { |p| [p.name, p.in] }
                   .map { |p| build_parameter(p, hint: base) }

      Ir::Operation.new(
        id: id,
        http_method: Ir::HttpMethod.deserialize(verb),
        path: path,
        tag: node.tags&.first || "default",
        parameters: parameters,
        request_body: (build_request_body(node.request_body, hint: base) if node.request_body),
        responses: build_responses(node.responses, hint: base),
        security: requirements(node.security, declared: raw(node).key?("security")),
        summary: node.summary,
        description: node.description,
        deprecated: !!node.deprecated?,
        extensions: extensions(node)
      )
    end

    sig { params(node: T.untyped, hint: String).returns(Ir::Parameter) }
    def build_parameter(node, hint:)
      info = Ir::ParameterInfo.new(
        name: node.name,
        identifier: Naming.identifier(node.name),
        schema: schema_for(node.schema, hint: "#{hint}#{Naming.pascal(node.name)}"),
        description: node.description,
        deprecated: !!node.deprecated?
      )
      explode = raw(node).key?("explode") ? !!node.explode? : nil

      case node.in
      when "path"
        Ir::PathParameter.new(info: info, style: path_style(node), explode: explode || false)
      when "query"
        Ir::QueryParameter.new(info: info, required: !!node.required?, style: query_style(node),
                               explode: explode.nil? || explode,
                               allow_reserved: !!node.allow_reserved?)
      when "header"
        Ir::HeaderParameter.new(info: info, required: !!node.required?, explode: explode || false)
      when "cookie"
        Ir::CookieParameter.new(info: info, required: !!node.required?,
                                explode: explode.nil? || explode)
      else
        raise SchemaError, "Parameter #{node.name.inspect} has an unknown `in: #{node.in.inspect}`."
      end
    end

    sig { params(node: T.untyped).returns(Ir::PathStyle) }
    def path_style(node)
      return Ir::PathStyle::Simple if node.style.nil?

      Ir::PathStyle.try_deserialize(node.style) ||
        raise(SchemaError,
              "Path parameter #{node.name.inspect} has style #{node.style.inspect}. " \
              "Path parameters support simple, label or matrix.")
    end

    sig { params(node: T.untyped).returns(Ir::QueryStyle) }
    def query_style(node)
      return Ir::QueryStyle::Form if node.style.nil?

      Ir::QueryStyle.try_deserialize(node.style) ||
        raise(SchemaError,
              "Query parameter #{node.name.inspect} has style #{node.style.inspect}. " \
              "Query parameters support form, spaceDelimited, pipeDelimited or deepObject.")
    end

    sig { params(node: T.untyped, hint: String).returns(Ir::RequestBody) }
    def build_request_body(node, hint:)
      Ir::RequestBody.new(contents: contents(node.content, hint: "#{hint}Body"),
                          required: !!node.required?, description: node.description)
    end

    sig { params(node: T.untyped, hint: String).returns(T::Array[Ir::Response]) }
    def build_responses(node, hint:)
      return [] if node.nil?

      node.map do |raw_status, response|
        status = Ir::Statuses.parse(raw_status.to_s)
        scoped = "#{hint}#{Ir::Statuses.constant(status)}"
        Ir::Response.new(
          status: status,
          contents: contents(response.content, hint: scoped),
          headers: (response.headers || {}).map do |name, header|
            Ir::Header.new(name: name, identifier: Naming.identifier(name),
                           schema: schema_for(header.schema, hint: "#{scoped}#{Naming.pascal(name)}"),
                           required: !!header.required?, description: header.description)
          end,
          description: response.description
        )
      end
    end

    sig { params(node: T.untyped, hint: String).returns(T::Array[Ir::Content]) }
    def contents(node, hint:)
      return [] if node.nil?

      multiple = node.keys.size > 1
      node.map do |media_type, media|
        suffix = multiple ? Naming.pascal(media_type.split("/").last.to_s.split("+").first.to_s) : ""
        Ir::Content.new(media_type: media_type,
                        schema: (schema_for(media.schema, hint: "#{hint}#{suffix}") if media.schema))
      end
    end

    sig { params(document: T.untyped).returns(T::Array[Ir::SecurityScheme]) }
    def build_security_schemes(document)
      (document.components&.security_schemes || {}).map do |name, node|
        case node.type
        when "apiKey"
          Ir::ApiKeyScheme.new(name: name, location: Ir::ApiKeyLocation.deserialize(node.in),
                               parameter_name: node.name, description: node.description)
        when "http"
          Ir::HttpScheme.new(name: name, scheme: node.scheme.to_s.downcase,
                             bearer_format: node.bearer_format, description: node.description)
        when "oauth2"
          Ir::OAuth2Scheme.new(name: name, scopes: oauth_scopes(node), description: node.description)
        when "openIdConnect"
          Ir::OpenIdConnectScheme.new(name: name, url: node.open_id_connect_url.to_s,
                                      description: node.description)
        else
          raise SchemaError, "Security scheme #{name.inspect} has unsupported type #{node.type.inspect}."
        end
      end
    end

    sig { params(node: T.untyped).returns(T::Hash[String, String]) }
    def oauth_scopes(node)
      flows = node.flows
      return {} if flows.nil?

      %i[implicit password client_credentials authorization_code].each_with_object({}) do |name, all|
        flow = flows.public_send(name)
        (flow&.scopes || {}).each { |scope, description| all[scope.to_s] = description.to_s }
      end
    end

    sig { params(node: T.untyped, declared: T::Boolean).returns(T.nilable(T::Array[Ir::SecurityRequirement])) }
    def requirements(node, declared: true)
      return nil if node.nil? || !declared

      node.map do |requirement|
        Ir::SecurityRequirement.new(
          schemes: requirement.to_h.transform_values { |scopes| Array(scopes).map(&:to_s) }
        )
      end
    end

    sig { params(node: T.untyped, hint: String, nullable: T::Boolean).returns(Ir::Schema) }
    def schema_for(node, hint:, nullable: false)
      return Ir::Untyped.new if node.nil?

      members = Array(node.all_of)
      if members.size == 1 && (node.properties.nil? || node.properties.empty?)
        return schema_for(members.first, hint: hint, nullable: nullable || !!node.nullable?)
      end

      name = if node.name
               rename(node.name)
             else
               (named_shape?(node) ? rename(hint) : nil)
             end
      if name
        register(node, name: name)
        return Ir::Ref.new(name: name, meta: meta_for(node, nullable: nullable))
      end

      structural(node, hint: hint, nullable: nullable)
    end

    sig { params(node: T.untyped).returns(T::Boolean) }
    def named_shape?(node)
      return true if node.enum || node.one_of || node.any_of || node.all_of&.any?

      !(node.properties.nil? || node.properties.empty?)
    end

    sig { params(node: T.untyped, hint: String, nullable: T::Boolean).returns(Ir::Schema) }
    def structural(node, hint:, nullable: false)
      meta = meta_for(node, nullable: nullable)

      case node.type
      when "string"
        Ir::StringSchema.new(format: node.format, min_length: node.min_length,
                             max_length: node.max_length, pattern: node.pattern, meta: meta)
      when "integer"
        Ir::IntegerSchema.new(format: node.format, minimum: node.minimum, maximum: node.maximum,
                              exclusive_minimum: !!node.exclusive_minimum?,
                              exclusive_maximum: !!node.exclusive_maximum?,
                              multiple_of: node.multiple_of, meta: meta)
      when "number"
        Ir::NumberSchema.new(format: node.format, minimum: node.minimum, maximum: node.maximum,
                             exclusive_minimum: !!node.exclusive_minimum?,
                             exclusive_maximum: !!node.exclusive_maximum?,
                             multiple_of: node.multiple_of, meta: meta)
      when "boolean"
        Ir::BooleanSchema.new(meta: meta)
      when "array"
        Ir::List.new(items: schema_for(node.items, hint: "#{hint}Item"), min_items: node.min_items,
                     max_items: node.max_items, unique_items: !!node.unique_items?, meta: meta)
      when "object"
        values = node.additional_properties_schema
        Ir::Freeform.new(values: (schema_for(values, hint: "#{hint}Value") if values),
                         min_properties: node.min_properties, max_properties: node.max_properties,
                         meta: meta)
      else
        Ir::Untyped.new(meta: meta)
      end
    end

    sig { params(node: T.untyped, name: String).void }
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

    sig { params(node: T.untyped, name: String).returns(Ir::TypeDef) }
    def build_type_def(node, name:)
      return enum_def(node, name: name) if node.enum
      return union_def(node, name: name) if node.one_of || node.any_of
      return object_def(node, name: name) if node.all_of&.any? || node.properties&.any?

      Ir::AliasDef.new(name: name, target: structural(node, hint: name), meta: meta_for(node))
    end

    sig { params(node: T.untyped, name: String).returns(Ir::TypeDef) }
    def enum_def(node, name:)
      values = node.enum.to_a
      kinds = values.map(&:class).uniq

      unless [[String], [Integer]].include?(kinds)
        raise SchemaError,
              "Enum #{name} has values of type #{kinds.map(&:name).sort.join(", ")}. " \
              "A T::Enum needs its values to be all strings or all integers."
      end

      Ir::EnumDef.new(
        name: name,
        members: values.map { |v| Ir::EnumMember.new(constant: Naming.enum_member(v), value: v) },
        meta: meta_for(node)
      )
    end

    sig { params(node: T.untyped, name: String).returns(Ir::TypeDef) }
    def union_def(node, name:)
      raw = node.one_of || node.any_of
      members = raw.each_with_index.map { |m, i| schema_for(m, hint: "#{name}Member#{i + 1}") }

      Ir::UnionDef.new(name: name, members: members, tag: union_tag(node, members),
                       meta: meta_for(node))
    end

    sig { params(node: T.untyped, name: String).returns(Ir::TypeDef) }
    def object_def(node, name:)
      properties = T.let({}, T::Hash[String, T.untyped])
      required = T.let(Set.new, T::Set[String])
      collect_properties(node, properties, required)

      Ir::ObjectDef.new(
        name: name,
        properties: properties.map do |pname, pnode|
          Ir::Property.new(name: pname, identifier: Naming.identifier(pname),
                           schema: schema_for(pnode, hint: "#{name}#{Naming.pascal(pname)}"),
                           required: required.include?(pname))
        end,
        additional_properties: additional_properties_for(node, name),
        meta: meta_for(node)
      )
    end

    sig { params(node: T.untyped, name: String).returns(T.nilable(Ir::Schema)) }
    def additional_properties_for(node, name)
      schema = node.additional_properties_schema
      return nil if schema.nil?

      schema_for(schema, hint: "#{name}Value")
    end

    sig { params(node: T.untyped, properties: T::Hash[String, T.untyped], required: T::Set[String]).void }
    def collect_properties(node, properties, required)
      Array(node.all_of).each { |member| collect_properties(member, properties, required) }
      (node.properties || {}).each { |pname, pnode| properties[pname] = pnode }
      Array(node.required).each { |name| required << name.to_s }
    end

    sig { params(node: T.untyped, members: T::Array[Ir::Schema]).returns(Ir::UnionTag) }
    def union_tag(node, members)
      discriminator = node.discriminator
      return Ir::Untagged.new if discriminator.nil?

      mapping = (discriminator.mapping || {})
                .to_h { |value, ref| [value.to_s, rename(ref.to_s.split("/").last.to_s)] }
      mapping = members.filter_map { |m| [m.name, m.name] if m.is_a?(Ir::Ref) }.to_h if mapping.empty?

      Ir::Tagged.new(property_name: discriminator.property_name, mapping: mapping)
    end

    sig { params(node: T.untyped, nullable: T::Boolean).returns(Ir::Meta) }
    def meta_for(node, nullable: false)
      data = raw(node)
      Ir::Meta.new(
        description: node.description,
        nullable: nullable || !!node.nullable?,
        deprecated: !!node.deprecated?,
        default: data.key?("default") ? Ir::Default.new(value: node.default) : nil,
        read_only: !!node.read_only?,
        write_only: !!node.write_only?,
        extensions: extensions(node),
        ruby_type: ruby_type_for(data)
      )
    end

    sig { params(node: T.untyped).returns(String) }
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
              "signatures, `x-ruby-codec` is what converts it -- a module extending, or an " \
              "instance of a class including, Oapi::Codec."
      end

      RubyType.new(type: type.to_s, codec: codec.to_s)
    end

    sig { params(name: String).returns(String) }
    def rename(name) = Naming.constant(@config.name_overrides.fetch(name, name))

    sig { params(node: T.untyped).returns(T::Hash[String, T.untyped]) }
    def extensions(node)
      raw(node).select { |k, _| k.to_s.start_with?("x-") }
    end

    sig { params(node: T.untyped).returns(T::Hash[String, T.untyped]) }
    def raw(node)
      input = node.node_context.input
      input.is_a?(Hash) ? input : {}
    end
  end
end
