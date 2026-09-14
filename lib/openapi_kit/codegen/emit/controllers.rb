# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class Controllers
        extend T::Sig
        include Emitter

        SOURCES = T.let(
          {
            "Path" => "path_params",
            "Query" => "query_params",
            "Headers" => "header_params",
            "Cookies" => "cookie_params"
          }.freeze,
          T::Hash[String, String]
        )

        sig { params(document: Model::Document, registry: TypeRegistry, config: Config).void }
        def initialize(document:, registry:, config:)
          @document = document
          @registry = registry
          @config = config
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          @document.operations.group_by(&:tag).map do |tag, operations|
            Source.file(path: "controllers/#{Naming.snake(tag)}_controller.rb",
                        modules: @config.modules + ["Controllers"]) do |buffer|
              emit_controller(buffer, tag, operations)
            end
          end
        end

        private

        sig { params(buffer: Buffer, tag: String, operations: T::Array[Model::Operation]).void }
        def emit_controller(buffer, tag, operations)
          buffer.nest("class #{Naming.pascal(tag)}Controller < #{controller_base}") do
            buffer.line("extend T::Sig")
            buffer.line("include ::OpenAPIKit::Rendering")

            operations.each do |operation|
              buffer.blank
              emit_action(buffer, operation)
            end

            buffer.blank
            buffer.line("private")
            buffer.blank
            emit_handler(buffer, tag)

            operations.select { |operation| principal?(operation) }.each do |operation|
              buffer.blank
              emit_authenticator(buffer, operation)
            end
          end
        end

        sig { returns(String) }
        def controller_base
          base = @config.controller_base
          base.start_with?("::") ? base : "::#{base}"
        end

        sig { params(buffer: Buffer, tag: String).void }
        def emit_handler(buffer, tag)
          interface = "#{@config.namespace}::Handlers::#{Handlers.module_name(tag)}"

          buffer.line("sig { returns(#{interface}) }")
          buffer.line("def handler = #{@config.namespace}.registry.#{Naming.snake(tag)}")
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_action(buffer, operation)
          scope = "#{@config.namespace}::Operations::#{Operations.module_name(operation)}"
          groups = grouped_parameters(operation)

          buffer.line("sig { void }")
          buffer.nest("def #{Naming.identifier(operation.id)}") do
            emit_authentication(buffer, operation)

            groups.each { |name, parameters| buffer.line(source_line(name, parameters)) }
            buffer.blank unless groups.empty?

            emit_decoded(buffer, operation, scope, groups)
            buffer.blank
            emit_dispatch(buffer, operation)
          end
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_authentication(buffer, operation)
          return unless principal?(operation)

          buffer.line("principal = #{authenticator_name(operation)}")
          buffer.blank
        end

        sig { params(operation: Model::Operation).returns(String) }
        def authenticator_name(operation) = "authenticate_#{Naming.identifier(operation.id)}"

        # Each alternative is one attempt, tried in the order the document lists them.
        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_authenticator(buffer, operation)
          requirements = @document.security_for(operation)

          buffer.line("sig { returns(#{Security.principal_type(requirements, @config)}) }")
          buffer.nest("def #{authenticator_name(operation)}") do
            buffer.line("::OpenAPIKit::Security.first_of(")
            buffer.indent do
              buffer.line("[")
              buffer.indent do
                requirements.reject(&:anonymous?).each { |requirement| buffer.line("#{attempt(requirement)},") }
              end
              buffer.line("]")
            end
            buffer.line(requirements.any?(&:anonymous?) ? ")" : ") || raise(::OpenAPIKit::SecurityError)")
          end
        end

        sig { params(requirement: Model::SecurityRequirement).returns(String) }
        def attempt(requirement)
          name = T.must(requirement.schemes.keys.first)
          scopes = T.must(requirement.schemes[name])
          reader = "#{@config.namespace}.registry.#{Naming.snake(name)}"

          "-> { #{reader}.authenticate(request: request, scopes: #{scopes.inspect}) }"
        end

        sig do
          params(buffer: Buffer, operation: Model::Operation, scope: String,
                 groups: T::Hash[String, T::Array[Model::Parameter]]).void
        end
        def emit_decoded(buffer, operation, scope, groups)
          buffer.line("decoded = #{scope}::Request.new(")
          buffer.indent do
            groups.each_key do |name|
              buffer.line("#{Naming.identifier(name)}: #{scope}::#{name}.new(")
              buffer.indent { emit_group_arguments(buffer, name, T.must(groups[name])) }
              buffer.line("),")
            end
            buffer.line("body: #{body_expression(operation)},") if body?(operation)
            buffer.line("principal: principal,") if principal?(operation)
            buffer.line("http_request: request")
          end
          buffer.line(")")
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_dispatch(buffer, operation)
          buffer.line("render_response(handler.#{Naming.identifier(operation.id)}(request: decoded))")
        end

        sig { params(buffer: Buffer, group: String, parameters: T::Array[Model::Parameter]).void }
        def emit_group_arguments(buffer, group, parameters)
          source = T.must(SOURCES[group])
          parameters.each do |parameter|
            info = Model::Parameter.info(parameter)
            expression = Decode.expression(source: source, key: info.name, schema: info.schema,
                                           required: Model::Parameter.required?(parameter), registry: @registry)
            buffer.line("#{info.identifier}: #{expression},")
          end
        end

        sig { params(group: String, parameters: T::Array[Model::Parameter]).returns(String) }
        def source_line(group, parameters)
          names = parameters.map { |parameter| Model::Parameter.info(parameter).name }

          "#{T.must(SOURCES[group])} = ::OpenAPIKit::Decode.gather(#{names.inspect}) " \
            "{ |name| #{lookup(group)} }"
        end

        sig { params(group: String).returns(String) }
        def lookup(group)
          case group
          when "Path" then "request.path_parameters[name.to_sym]"
          when "Query" then "request.query_parameters[name]"
          when "Headers" then "request.headers[name]"
          when "Cookies" then "request.cookies[name]"
          else raise SchemaError, "unknown parameter group #{group}"
          end
        end

        sig { params(operation: Model::Operation).returns(T::Hash[String, T::Array[Model::Parameter]]) }
        def grouped_parameters(operation)
          reject_unsupported_styles(operation)

          {
            "Path" => Model::PathParameter, "Query" => Model::QueryParameter,
            "Headers" => Model::HeaderParameter, "Cookies" => Model::CookieParameter
          }.filter_map do |name, kind|
            found = operation.parameters.grep(kind)
            found.empty? ? nil : [name, found]
          end.to_h
        end

        sig { params(operation: Model::Operation).void }
        def reject_unsupported_styles(operation)
          operation.parameters.each do |parameter|
            style = unsupported_style(parameter)
            next if style.nil?

            raise SchemaError,
                  "#{operation.id} declares parameter " \
                  "#{Model::Parameter.info(parameter).name.inspect} with style #{style.inspect}, which " \
                  "openapi_kit does not decode yet. Supported styles are simple for path and form for query."
          end
        end

        sig { params(parameter: Model::Parameter).returns(T.nilable(String)) }
        def unsupported_style(parameter)
          case parameter
          when Model::PathParameter
            parameter.style == Model::PathStyle::Simple ? nil : parameter.style.serialize
          when Model::QueryParameter
            parameter.style == Model::QueryStyle::Form ? nil : parameter.style.serialize
          end
        end

        sig { params(operation: Model::Operation).returns(T::Boolean) }
        def principal?(operation)
          !@config.principal.nil? && !@document.security_for(operation).empty?
        end

        sig { params(operation: Model::Operation).returns(T::Boolean) }
        def body?(operation)
          body = operation.request_body
          !body.nil? && !body.contents.empty?
        end

        sig { params(operation: Model::Operation).returns(String) }
        def body_expression(operation)
          body = T.must(operation.request_body)
          schema = T.must(body.contents.first).schema
          return "nil" if schema.nil?

          source = body_source(schema)
          inner = @registry.from_form_expr(schema, value: source) ||
                  @registry.from_wire_expr(schema, value: source)
          body.required ? inner : "(#{inner} if #{body_present(schema)})"
        end

        # Rails' JSON parameter parser wraps a body that is not a JSON object as
        # { _json: parsed }, so a top-level array or scalar arrives under that key.
        sig { params(schema: Model::Schema).returns(String) }
        def body_source(schema)
          @registry.object?(schema) ? "request.request_parameters" : %(request.request_parameters["_json"])
        end

        sig { params(schema: Model::Schema).returns(String) }
        def body_present(schema)
          return "request.request_parameters.any?" if @registry.object?(schema)

          %(request.request_parameters.key?("_json"))
        end
      end
    end
  end
end
