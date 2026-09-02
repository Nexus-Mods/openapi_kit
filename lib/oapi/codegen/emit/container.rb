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

        sig { params(name: String).returns(String) }
        def self.authenticator_key_for(name) = "security.#{Naming.snake(name)}"

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if @document.operations.empty?

          [Source.file(path: "#{@config.module_path}/container.rb",
                       modules: @config.modules + ["Container"]) { |buffer| emit_body(buffer) }]
        end

        private

        sig { params(tag: String).returns(String) }
        def key_for(tag) = @config.container_key("handlers", Naming.snake(tag))

        sig { params(buffer: Buffer).void }
        def emit_authenticators(buffer)
          buffer.line("AUTHENTICATORS = T.let(")
          buffer.indent do
            buffer.line("{")
            buffer.indent do
              authenticated.each do |name|
                interface = "#{@config.namespace}::Security::#{Emit::Security.module_name(name)}"
                key = @config.container_key("security", Naming.snake(name))
                buffer.line("#{key.inspect} => #{interface},")
              end
            end
            buffer.line("}.freeze,")
            buffer.line("T::Hash[::String, T::Module[T.anything]]")
          end
          buffer.line(")")
          buffer.blank
        end

        sig { returns(T::Array[String]) }
        def authenticated
          @document.security_schemes
                   .map { |scheme| Model::SecurityScheme.name_of(scheme) }
                   .select { |name| @config.principals.key?(name) }
        end

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
          emit_authenticators(buffer)
          buffer.line("sig { params(container: T.untyped).void }")
          buffer.nest("def self.verify!(container)") do
            buffer.line("::Oapi::Container.verify!(container, HANDLERS.merge(AUTHENTICATORS))")
          end
        end
      end
    end
  end
end
