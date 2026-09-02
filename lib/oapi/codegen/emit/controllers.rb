# typed: strict
# frozen_string_literal: true

module Oapi
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
            Source.file(path: "#{@config.module_path}/#{Naming.snake(tag)}_controller.rb",
                        modules: @config.modules) do |buffer|
              emit_controller(buffer, tag, operations)
            end
          end
        end

        private

        sig { params(buffer: Buffer, tag: String, operations: T::Array[Model::Operation]).void }
        def emit_controller(buffer, tag, operations)
          buffer.nest("class #{Naming.pascal(tag)}Controller < #{controller_base}") do
            buffer.line("extend T::Sig")

            operations.each do |operation|
              buffer.blank
              emit_action(buffer, operation)
            end

            buffer.blank
            buffer.line("private")
            buffer.blank
            emit_handler(buffer, tag)
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
          key = @config.container_key("handlers", Naming.snake(tag))

          buffer.line("sig { returns(#{interface}) }")
          buffer.nest("def handler") do
            buffer.line("T.cast(oapi_container.resolve(#{key.inspect}), #{interface})")
          end
        end

        sig { params(buffer: Buffer, operation: Model::Operation).void }
        def emit_action(buffer, operation)
          scope = "#{@config.namespace}::Operations::#{Operations.module_name(operation)}"
          groups = grouped_parameters(operation)

          buffer.line("sig { void }")
          buffer.nest("def #{Naming.identifier(operation.id)}") do
            groups.each { |name, parameters| buffer.line(source_line(name, parameters)) }
            buffer.blank unless groups.empty?

            buffer.line("decoded = #{scope}::Request.new(")
            buffer.indent do
              groups.each_key do |name|
                buffer.line("#{Naming.identifier(name)}: #{scope}::#{name}.new(")
                buffer.indent { emit_group_arguments(buffer, name, T.must(groups[name])) }
                buffer.line("),")
              end
              buffer.line("body: #{body_expression(operation)},") if body?(operation)
              buffer.line("http_request: request")
            end
            buffer.line(")")
            buffer.blank
            buffer.line("response = handler.#{Naming.identifier(operation.id)}(request: decoded)")
            buffer.line("body = response.to_wire")
            buffer.blank
            buffer.line("return head(response.status) if body.nil?")
            buffer.blank
            buffer.line("render(json: body, status: response.status, content_type: response.content_type)")
          end
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

          case group
          when "Path" then "path_params = request.path_parameters.transform_keys(&:to_s)"
          when "Query" then "query_params = request.query_parameters"
          when "Headers" then gather_line("header_params", "request.headers", names)
          when "Cookies" then gather_line("cookie_params", "request.cookie_jar", names)
          else raise SchemaError, "unknown parameter group #{group}"
          end
        end

        sig { params(local: String, source: String, names: T::Array[String]).returns(String) }
        def gather_line(local, source, names)
          "#{local} = ::Oapi::Decode.gather(#{names.inspect}) { |name| #{source}[name] }"
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
                  "oapi does not decode yet. Supported styles are simple for path and form for query."
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
        def body?(operation)
          body = operation.request_body
          !body.nil? && !body.contents.empty?
        end

        sig { params(operation: Model::Operation).returns(String) }
        def body_expression(operation)
          body = T.must(operation.request_body)
          schema = T.must(body.contents.first).schema
          return "nil" if schema.nil?

          inner = @registry.from_wire_expr(schema, value: "request.request_parameters")
          body.required ? inner : "(#{inner} if request.request_parameters.present?)"
        end
      end
    end
  end
end
