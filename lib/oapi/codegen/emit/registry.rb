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
        def emit_class(buffer)
          buffer.nest("class Registry < T::Struct") do
            buffer.line("extend T::Sig")
            buffer.blank
            slots.each { |slot| buffer.line("const :#{slot.reader}, #{slot.interface}") }
            buffer.blank
            emit_swap(buffer)
          end
        end

        # Replace individual pieces without restating the rest, for a test that fakes one.
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
              slots.each { |slot| buffer.line("#{slot.reader}: #{slot.reader} || self.#{slot.reader},") }
            end
            buffer.line(")")
          end
        end

        sig { params(default: T.nilable(String)).returns(String) }
        def keywords(default: nil)
          slots.map { |slot| "#{slot.reader}:#{" #{default}" if default}" }.join(", ")
        end
      end
    end
  end
end
