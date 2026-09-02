# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Handlers
        extend T::Sig

        sig { params(document: Ir::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { params(tag: String).returns(String) }
        def self.module_name(tag) = Naming.pascal(tag)

        sig { returns(T::Array[SourceFile]) }
        def render
          by_tag.map do |tag, operations|
            Source.file(path: "#{@config.module_path}/handlers/#{Naming.snake(tag)}.rb",
                        modules: @config.modules + ["Handlers"]) do |buffer|
              emit_interface(buffer, tag, operations)
            end
          end
        end

        private

        sig { returns(T::Hash[String, T::Array[Ir::Operation]]) }
        def by_tag = @document.operations.group_by(&:tag)

        sig { params(buffer: Buffer, tag: String, operations: T::Array[Ir::Operation]).void }
        def emit_interface(buffer, tag, operations)
          buffer.nest("module #{Handlers.module_name(tag)}") do
            buffer.line("extend T::Sig")
            buffer.line("extend T::Helpers")
            buffer.line("interface!")

            operations.each do |operation|
              buffer.blank
              emit_method(buffer, operation)
            end
          end
        end

        sig { params(buffer: Buffer, operation: Ir::Operation).void }
        def emit_method(buffer, operation)
          scope = "#{@config.namespace}::Operations::#{Emit::Operations.module_name(operation)}"

          buffer.nest("sig do") do
            buffer.line("abstract")
            buffer.indent do
              buffer.line(".params(request: #{scope}::Request)")
              buffer.line(".returns(#{scope}::Response)")
            end
          end
          buffer.line("def #{Naming.identifier(operation.id)}(request:); end")
        end
      end
    end
  end
end
