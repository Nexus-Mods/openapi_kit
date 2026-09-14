# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      # The typed boundary between openapi_kit's interfaces and an application's objects. Rails
      # instantiates controllers itself, so a controller cannot be handed the registry: it
      # reads it from the accessor, which an application assigns at boot.
      class Registry
        extend T::Sig
        include Emitter

        # One entry per thing an application must supply.
        class Slot < T::Struct
          const :reader, String
          const :interface, String
        end

        sig { params(document: Model::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if slots.empty?

          [
            Source.file(path: "#{@config.module_path}/registry.rb",
                        modules: @config.modules) { |buffer| emit_registry(buffer) },
            Source.file(path: "#{@config.module_path}.rb",
                        modules: @config.modules) { |buffer| emit_accessor(buffer) }
          ]
        end

        private

        sig { returns(T::Array[Slot]) }
        def slots
          handlers = @document.tags.map do |tag|
            Slot.new(reader: Naming.snake(tag),
                     interface: "#{@config.namespace}::Handlers::#{Emit::Handlers.module_name(tag)}")
          end

          handlers + authenticated.map do |name|
            Slot.new(reader: Naming.snake(name),
                     interface: "#{@config.namespace}::Security::#{Emit::Security.module_name(name)}")
          end
        end

        sig { returns(T::Array[String]) }
        def authenticated
          return [] if @config.principal.nil?

          @document.operations.flat_map do |operation|
            @document.security_for(operation).flat_map { |requirement| requirement.schemes.keys }
          end.uniq
        end

        sig { params(buffer: Buffer).void }
        def emit_registry(buffer)
          buffer.nest("class Registry < T::Struct") do
            slots.each { |slot| buffer.line("const :#{slot.reader}, #{slot.interface}") }
          end
        end

        # Rails instantiates controllers itself, so a controller cannot be handed the
        # registry. It reads it from here, and an application assigns it at boot.
        sig { params(buffer: Buffer).void }
        def emit_accessor(buffer)
          buffer.line("extend T::Sig")
          buffer.blank
          buffer.line("@registry = T.let(nil, T.nilable(Registry))")
          buffer.blank
          buffer.line("sig { params(registry: Registry).void }")
          buffer.nest("def self.registry=(registry)") do
            buffer.line("@registry = registry")
          end
          buffer.blank
          buffer.line("sig { returns(Registry) }")
          buffer.nest("def self.registry") do
            buffer.line("@registry || raise(")
            buffer.indent { unset_message.each { |line| buffer.line(line) } }
            buffer.line(")")
          end
        end

        sig { returns(T::Array[String]) }
        def unset_message
          namespace = @config.namespace
          [
            %("#{namespace}.registry has not been assigned. Build one in an initializer, " \\),
            %("e.g. #{namespace}.registry = #{namespace}::Registry.new(...).")
          ]
        end
      end
    end
  end
end
