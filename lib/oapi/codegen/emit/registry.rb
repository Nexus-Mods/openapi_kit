# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    module Emit
      # The typed boundary between oapi's interfaces and an application's objects. Fields
      # are thunks, so nothing is built until first use, and Sorbet checks that every
      # interface has an implementation of the right type at the call site, which is
      # earlier and stricter than any boot-time check.
      class Registry
        extend T::Sig
        include Emitter

        # One entry per thing an application must supply.
        class Slot < T::Struct
          const :reader, String
          const :interface, String
          const :key, String
        end

        sig { params(document: Model::Document, config: Config).void }
        def initialize(document:, config:)
          @document = document
          @config = config
        end

        sig { override.returns(T::Array[SourceFile]) }
        def render
          return [] if slots.empty?

          [Source.file(path: "#{@config.module_path}/registry.rb",
                       modules: @config.modules) { |buffer| emit_class(buffer) }]
        end

        private

        sig { returns(T::Array[Slot]) }
        def slots
          handlers = @document.tags.map do |tag|
            Slot.new(reader: Naming.snake(tag),
                     interface: "#{@config.namespace}::Handlers::#{Emit::Handlers.module_name(tag)}",
                     key: @config.container_key("handlers", Naming.snake(tag)))
          end

          handlers + authenticated.map do |name|
            Slot.new(reader: Naming.snake(name),
                     interface: "#{@config.namespace}::Security::#{Emit::Security.module_name(name)}",
                     key: @config.container_key("security", Naming.snake(name)))
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
        def emit_class(buffer)
          buffer.nest("class Registry") do
            buffer.line("extend T::Sig")
            buffer.blank
            emit_initialize(buffer)
            buffer.blank
            emit_readers(buffer)
            emit_swap(buffer)
            buffer.blank
            emit_from(buffer)
          end
        end

        sig { params(buffer: Buffer).void }
        def emit_initialize(buffer)
          buffer.line("sig do")
          buffer.indent { buffer.nest_call("params", slots.map { |slot| [slot.reader, thunk(slot)] }, tail: ".void") }
          buffer.line("end")
          buffer.nest("def initialize(#{keywords})") do
            slots.each do |slot|
              buffer.line("@#{slot.reader}_factory = #{slot.reader}")
              buffer.line("@#{slot.reader} = T.let(nil, T.nilable(#{slot.interface}))")
            end
          end
        end

        sig { params(buffer: Buffer).void }
        def emit_readers(buffer)
          slots.each do |slot|
            buffer.line("sig { returns(#{slot.interface}) }")
            buffer.line("def #{slot.reader} = @#{slot.reader} ||= @#{slot.reader}_factory.call")
            buffer.blank
          end
        end

        # Replace individual pieces without rebuilding the rest, for a test that fakes one.
        sig { params(buffer: Buffer).void }
        def emit_swap(buffer)
          buffer.line("sig do")
          buffer.indent do
            arguments = slots.map { |slot| [slot.reader, "T.nilable(#{slot.interface})"] }
            buffer.nest_call("params", arguments, tail: ".returns(Registry)")
          end
          buffer.line("end")
          buffer.nest("def swap(#{keywords(default: "nil")})") do
            buffer.line("Registry.new(")
            buffer.indent do
              slots.each do |slot|
                reader = slot.reader
                buffer.line("#{reader}: #{reader} ? -> { #{reader} } : @#{reader}_factory,")
              end
            end
            buffer.line(")")
          end
        end

        # For an application that would rather keep its wiring in a container: the casts
        # live here, thunked so a resolve is still deferred.
        sig { params(buffer: Buffer).void }
        def emit_from(buffer)
          buffer.line("sig { params(container: T.untyped).returns(Registry) }")
          buffer.nest("def self.from(container)") do
            buffer.line("new(")
            buffer.indent do
              slots.each do |slot|
                buffer.line("#{slot.reader}: -> { T.cast(container.resolve(#{slot.key.inspect}), #{slot.interface}) },")
              end
            end
            buffer.line(")")
          end
        end

        sig { params(slot: Slot).returns(String) }
        def thunk(slot) = "T.proc.returns(#{slot.interface})"

        sig { params(default: T.nilable(String)).returns(String) }
        def keywords(default: nil)
          slots.map { |slot| "#{slot.reader}:#{" #{default}" if default}" }.join(", ")
        end
      end
    end
  end
end
