# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      class Routes
        extend T::Sig
        include Emitter

        sig { params(document: Model::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if @document.operations.empty?

          [
            Source.file(path: "#{@config.module_path}/routes.rb",
                        modules: @config.modules + ["Routes"]) { |buffer| emit_body(buffer) }
          ]
        end

        private

        sig { params(buffer: Buffer).void }
        def emit_body(buffer)
          buffer.line("extend T::Sig")
          buffer.blank
          buffer.line("sig { params(mapper: ::ActionDispatch::Routing::Mapper).void }")
          buffer.nest("def self.draw(mapper)") do
            ordered(@document.operations).each { |operation| buffer.line(route_for(operation)) }
          end
        end

        # Rails matches routes in declaration order, so a templated segment declared first
        # swallows a concrete one: /mods/{id} would answer GET /mods/featured. OpenAPI paths
        # are unordered, so the emitter imposes concrete-before-templated per segment.
        sig { params(operations: T::Array[Model::Operation]).returns(T::Array[Model::Operation]) }
        def ordered(operations)
          operations.each_with_index.sort_by { |operation, index| [template_flags(operation), index] }
                    .map(&:first)
        end

        sig { params(operation: Model::Operation).returns(T::Array[Integer]) }
        def template_flags(operation)
          operation.path.split("/").reject(&:empty?).map { |segment| segment.start_with?("{") ? 1 : 0 }
        end

        sig { params(operation: Model::Operation).returns(String) }
        def route_for(operation)
          verb = operation.http_method.serialize
          controller = "#{@config.module_path}/controllers/#{Naming.snake(operation.tag)}"
          target = "#{controller}##{Naming.identifier(operation.id)}"

          "mapper.#{verb}(#{path_for(operation).inspect}, to: #{target.inspect}, format: false)"
        end

        sig { params(operation: Model::Operation).returns(String) }
        def path_for(operation)
          operation.path.scan(/\{([^}]*)\}/).flatten.each do |name|
            next if name.match?(/\A\w+\z/)

            raise SchemaError,
                  "#{operation.path} has the path template {#{name}}, which Rails cannot route. " \
                  "A path parameter name may contain only letters, digits and underscores."
          end

          operation.path.gsub(/\{(\w+)}/, ':\1')
        end
      end
    end
  end
end
