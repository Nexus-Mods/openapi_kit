# typed: strict
# frozen_string_literal: true

module Oapi
  module Emit
    class Container
      extend T::Sig

      sig { params(document: Ir::Document, config: Config).void }
      def initialize(document:, config:)
        @document = document
        @config = config
      end

      sig { params(tag: String).returns(String) }
      def key_for(tag) = @config.container_key("handlers", Naming.snake(tag))

      sig { returns(String) }
      def render
        buffer = Buffer.new
        buffer.line("# typed: strict")
        buffer.line("# frozen_string_literal: true")
        buffer.blank
        buffer.nest_modules(@config.modules + ["Container"]) do
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
        buffer.to_s
      end
    end
  end
end
