# typed: strict
# frozen_string_literal: true

module Oapi
  module Codegen
    class Generator
      extend T::Sig

      sig { returns(T::Array[String]) }
      attr_reader :warnings

      sig { params(config: Config).void }
      def initialize(config:)
        @config = config
        @warnings = T.let([], T::Array[String])
      end

      sig { returns(T::Array[Pathname]) }
      def generate
        document = Loader.new(config: @config).parse
        registry = TypeRegistry.for(document, @config)
        writer = Writer.new(output: @config.output)

        files = emitters(document, registry).flat_map(&:render)

        writer.clean!
        files.each { |file| writer.write(file.path, file.contents) }
        @warnings = registry.warnings
        writer.written
      end

      private

      sig { params(document: Ir::Document, registry: TypeRegistry).returns(T::Array[T.untyped]) }
      def emitters(document, registry)
        [
          Emit::Types.new(document: document, registry: registry, config: @config),
          Emit::Operations.new(document: document, registry: registry, config: @config),
          Emit::Handlers.new(document: document, config: @config),
          Emit::Container.new(document: document, config: @config)
        ]
      end
    end
  end
end
