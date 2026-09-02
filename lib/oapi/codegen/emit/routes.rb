# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Routes
        extend T::Sig

        sig { params(document: Ir::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { returns(T::Array[SourceFile]) }
        def render
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
            @document.operations.each { |operation| buffer.line(route_for(operation)) }
          end
        end

        sig { params(operation: Ir::Operation).returns(String) }
        def route_for(operation)
          verb = operation.http_method.serialize
          target = "#{@config.module_path}/#{Naming.snake(operation.tag)}##{Naming.identifier(operation.id)}"

          "mapper.#{verb}(#{path_for(operation).inspect}, to: #{target.inspect})"
        end

        sig { params(operation: Ir::Operation).returns(String) }
        def path_for(operation)
          "#{@config.route_prefix}#{operation.path.gsub(/\{(\w+)\}/, ':\1')}"
        end
      end
    end
  end
end
