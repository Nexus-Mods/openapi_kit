# typed: strict
# frozen_string_literal: true

module OpenAPIKit
  module Codegen
    module Emit
      # The typed boundary between openapi_kit's interfaces and an application's objects. Rails
      # instantiates controllers itself, so a controller cannot be handed the registry: it
      # reads the one an application assigned at boot.
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
            Source.file(path: "registry.rb",
                        modules: @config.modules) { |buffer| emit_registry(buffer) }
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
            buffer.line("extend T::Sig")
            buffer.blank
            slots.each { |slot| buffer.line("const :#{slot.reader}, #{slot.interface}") }
            buffer.blank
            emit_accessor(buffer)
          end
        end

        # Rails instantiates controllers itself, so a controller cannot be handed the
        # registry. It reads the one here, which an application assigns at boot.
        sig { params(buffer: Buffer).void }
        def emit_accessor(buffer)
          buffer.line("@instance = T.let(nil, T.nilable(Registry))")
          buffer.blank
          buffer.line("sig { params(registry: Registry).void }")
          buffer.nest("def self.instance=(registry)") do
            buffer.line("@instance = registry")
          end
          buffer.blank
          buffer.line("sig { returns(Registry) }")
          buffer.nest("def self.instance") do
            buffer.line("@instance || raise(")
            buffer.indent { unassigned_message.each { |line| buffer.line(line) } }
            buffer.line(")")
          end
        end

        sig { returns(T::Array[String]) }
        def unassigned_message
          namespace = @config.namespace
          [
            %("#{namespace}::Registry.instance has not been assigned. Build one in an " \\),
            %("initializer, e.g. #{namespace}::Registry.instance = #{namespace}::Registry.new(...).")
          ]
        end
      end
    end
  end
end
