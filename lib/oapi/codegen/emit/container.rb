# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      class Container
        extend T::Sig
        include Emitter

        sig { params(document: Model::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { params(tag: String).returns(String) }
        def key_for(tag) = @config.container_key("handlers", Naming.snake(tag))

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if @document.operations.empty?

          [Source.file(path: "#{@config.module_path}/container.rb",
                       modules: @config.modules + ["Container"]) { |buffer| emit_body(buffer) }]
        end

        private

        sig { params(buffer: Buffer).void }
        def emit_body(buffer)
          buffer.line("extend T::Sig")
          buffer.blank
          buffer.line("HANDLERS = T.let(")
          buffer.indent do
            buffer.line("{")
            buffer.indent do
              @document.tags.each do |tag|
                interface = "#{@config.namespace}::Handlers::#{Emit::Handlers.module_name(tag)}"
                buffer.line("#{key_for(tag).inspect} => #{interface},")
              end
            end
            buffer.line("}.freeze,")
            buffer.line("T::Hash[::String, T::Module[T.anything]]")
          end
          buffer.line(")")
          buffer.blank
          buffer.line("sig { params(container: T.untyped).void }")
          buffer.line("def self.verify!(container) = ::Oapi::Container.verify!(container, HANDLERS)")
        end
      end
    end
  end
end
