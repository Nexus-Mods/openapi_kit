# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      # The typed boundary between oapi's interfaces and an application's objects. Rails
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
          buffer.nest("module Registry") do
            buffer.line("extend T::Sig")
            buffer.line("include Kernel")
            buffer.blank
            emit_readers(buffer)
            emit_factory(buffer)
            buffer.blank
            emit_values(buffer)
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
          buffer.line("def self.registry=(registry)")
          buffer.indent { buffer.line("@registry = registry") }
          buffer.line("end")
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

        # Plain signatures rather than abstract ones, so an implementation may be a struct
        # whose props satisfy them without restating every reader.
        sig { params(buffer: Buffer).void }
        def emit_readers(buffer)
          slots.each do |slot|
            reader = slot.reader
            buffer.line("sig { returns(#{slot.interface}) }")
            buffer.line(%(def #{reader} = raise(NotImplementedError, "\#{self.class} must provide #{reader}")))
            buffer.blank
          end
        end

        # Reads as constructing a Registry, and what it builds is an implementation
        # detail: an application that wants something else implements the interface.
        sig { params(buffer: Buffer).void }
        def emit_factory(buffer)
          buffer.line("sig do")
          buffer.indent do
            arguments = slots.map { |slot| [slot.reader, slot.interface] }
            buffer.nest_call("params", arguments, tail: ".returns(Registry)")
          end
          buffer.line("end")
          buffer.nest("def self.new(#{slots.map { |slot| "#{slot.reader}:" }.join(", ")})") do
            buffer.line("Values.new(")
            buffer.indent do
              slots.each { |slot| buffer.line("#{slot.reader}: #{slot.reader},") }
            end
            buffer.line(")")
          end
        end

        sig { params(buffer: Buffer).void }
        def emit_values(buffer)
          buffer.nest("class Values < T::Struct") do
            buffer.line("include Registry")
            buffer.blank
            slots.each { |slot| buffer.line("const :#{slot.reader}, #{slot.interface}") }
          end
        end
      end
    end
  end
end
