# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Operations
        extend T::Sig
        include Emitter

        sig { params(document: Model::Document, registry: TypeRegistry, config: Config).void }
        def initialize(document:, registry:, config:)
          @document = document
          @registry = registry
          @config = config
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          @document.operations.map do |operation|
            Source.file(path: "#{@config.module_path}/operations/#{Naming.snake(operation.id)}.rb",
                        modules: @config.modules + ["Operations"]) do |buffer|
              emit_operation(buffer, operation)
            end
          end
        end

        sig { params(operation: Model::Operation).returns(String) }
        def self.module_name(operation) = Naming.pascal(operation.id)

        GROUPS = T.let(
          {
            "Path" => Model::PathParameter,
            "Query" => Model::QueryParameter,
            "Headers" => Model::HeaderParameter,
            "Cookies" => Model::CookieParameter
          }.freeze,
          T::Hash[String, T::Class[T.anything]]
        )

        private

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_operation(buffer, operation)
          buffer.nest("module #{Operations.module_name(operation)}") do
            emit_parameter_structs(buffer, operation)
            emit_request(buffer, operation)
            buffer.blank
            emit_response(buffer, operation)
          end
        end

        sig { params(operation: Model::Operation).returns(T::Hash[String, T::Array[Model::Parameter]]) }
        def groups(operation)
          GROUPS.filter_map do |name, kind|
            found = operation.parameters.grep(kind)
            found.empty? ? nil : [name, found]
          end.to_h
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_parameter_structs(buffer, operation)
          groups(operation).each do |name, parameters|
            buffer.nest("class #{name} < T::Struct") do
              buffer.line("extend T::Sig")
              buffer.blank
              parameters.each { |parameter| buffer.line(parameter_prop(parameter)) }
            end
            buffer.blank
          end
        end

        sig { params(parameter: Model::Parameter).returns(String) }
        def parameter_prop(parameter)
          info = Model::Parameter.info(parameter)
          meta = Model::Schema.meta(info.schema)
          base = @registry.sorbet_type(info.schema)
          default = meta.default

          if default
            clause = Defaults.clause(schema: info.schema, default: default, registry: @registry)
            type = Defaults.nilable?(required: true, meta: meta) ? "T.nilable(#{base})" : base
            return "const :#{info.identifier}, #{type}, #{clause}"
          end

          return "const :#{info.identifier}, #{base}" if Model::Parameter.required?(parameter) && !meta.nullable

          "const :#{info.identifier}, T.nilable(#{base})"
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_request(buffer, operation)
          buffer.nest("class Request < T::Struct") do
            buffer.line("extend T::Sig")
            buffer.blank
            groups(operation).each_key { |name| buffer.line("const :#{Naming.identifier(name)}, #{name}") }
            body = body_type(operation)
            buffer.line("const :body, #{body}") if body
            principal = principal_type(operation)
            buffer.line("const :principal, #{principal}") if principal
            buffer.line("const :http_request, ::ActionDispatch::Request")
          end
        end

        # Present only when `principals` is configured and the operation is protected:
        # whatever the alternative that authenticated the request produced.
        sig { params(operation: Model::Operation).returns(T.nilable(String)) }
        def principal_type(operation)
          return nil if @config.principal.nil?

          requirements = @document.security_for(operation)
          return nil if requirements.empty?

          Security.principal_type(requirements, @config)
        end

        sig { params(operation: Model::Operation).returns(T.nilable(String)) }
        def body_type(operation)
          body = operation.request_body
          return nil if body.nil?

          content = single_content(body.contents, "the request body of #{operation.id}")
          schema = content&.schema
          return nil if schema.nil?

          type = @registry.sorbet_type(schema)
          body.required ? type : "T.nilable(#{type})"
        end

        sig { params(contents: T::Array[Model::Content], where: String).returns(T.nilable(Model::Content)) }
        def single_content(contents, where)
          return nil if contents.empty?
          return contents.first if contents.one?

          raise SchemaError,
                "#{where} declares #{contents.size} content types " \
                "(#{contents.map(&:media_type).join(", ")}). oapi supports one content type per " \
                "request body; split the alternatives into separate operations."
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_response(buffer, operation)
          variants = variants_for(operation)

          buffer.nest("module Response") do
            buffer.line("extend T::Helpers")
            buffer.line("include ::Oapi::Response")
            buffer.line("abstract!")
            buffer.line("sealed!")
          end

          variants.each do |variant|
            buffer.blank
            emit_variant(buffer, variant)
          end
        end

        module Payload
          extend T::Helpers
          abstract!
          sealed!

          class Empty < T::Struct
            include Payload
          end

          class Json < T::Struct
            include Payload

            const :schema, Model::Schema
          end

          class Stream < T::Struct
            include Payload
          end
        end

        class Variant < T::Struct
          const :name, String
          const :status, Model::Status
          const :media_type, T.nilable(String)
          const :payload, Payload
        end

        sig { params(operation: Model::Operation).returns(T::Array[Variant]) }
        def variants_for(operation)
          operation.responses.flat_map do |response|
            base = Model::Status.constant(response.status)
            next [empty_variant(base, response.status)] if response.contents.empty?

            multiple = response.contents.size > 1
            response.contents.map do |content|
              suffix = multiple ? Naming.pascal(content.media_type.split("/").last.to_s.split("+").first.to_s) : ""
              Variant.new(name: "#{base}#{suffix}", status: response.status,
                          media_type: content.media_type, payload: payload_for(content))
            end
          end
        end

        sig { params(name: String, status: Model::Status).returns(Variant) }
        def empty_variant(name, status)
          Variant.new(name: name, status: status, media_type: nil, payload: Payload::Empty.new)
        end

        sig { params(content: Model::Content).returns(Payload) }
        def payload_for(content)
          schema = content.schema
          return Payload::Empty.new if schema.nil?
          return Payload::Stream.new if Model::Schema.file?(schema)

          Payload::Json.new(schema: schema)
        end

        sig { params(buffer: Buffer, variant: Variant).void }
        def emit_variant(buffer, variant)
          buffer.nest("class #{variant.name} < T::Struct") do
            buffer.line("extend T::Sig")
            buffer.line("include Response")
            buffer.blank

            props = variant_props(variant)
            props.each { |prop| buffer.line(prop) }
            buffer.blank unless props.empty?

            buffer.line("sig { override.returns(::Integer) }")
            buffer.line(status_method(variant.status))
            buffer.blank
            buffer.line("sig { override.returns(::Oapi::Body) }")
            buffer.line("def to_body = #{to_body(variant.payload)}")
            buffer.blank
            buffer.line("sig { override.returns(T.nilable(::String)) }")
            buffer.line("def content_type = #{variant.media_type.inspect}")
          end
        end

        sig { params(variant: Variant).returns(T::Array[String]) }
        def variant_props(variant)
          props = payload_props(variant.payload)
          return props unless variant.status.is_a?(Model::DefaultStatus)

          props + ["const :status_code, ::Integer"]
        end

        sig { params(payload: Payload).returns(T::Array[String]) }
        def payload_props(payload)
          case payload
          when Payload::Empty then []
          when Payload::Json then ["const :body, #{@registry.sorbet_type(payload.schema)}"]
          when Payload::Stream then ["const :body, #{TypeRegistry::BYTES}"]
          else T.absurd(payload)
          end
        end

        sig { params(payload: Payload).returns(String) }
        def to_body(payload)
          case payload
          when Payload::Empty then "::Oapi::Body::Empty.new"
          when Payload::Json
            "::Oapi::Body::Json.new(wire: #{@registry.to_wire_expr(payload.schema, value: "body")})"
          when Payload::Stream then "body"
          else T.absurd(payload)
          end
        end

        sig { params(status: Model::Status).returns(String) }
        def status_method(status)
          case status
          when Model::StatusCode then "def status = #{status.code}"
          when Model::StatusRange then "def status = #{status.hundreds * 100}"
          when Model::DefaultStatus then "def status = status_code"
          else T.absurd(status)
          end
        end
      end
    end
  end
end
