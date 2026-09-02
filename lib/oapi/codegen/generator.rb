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
        loader = Loader.new(config: @config)
        document = loader.parse
        registry = TypeRegistry.for(document, @config)
        writer = Writer.new(output: @config.output)

        files = emitters(document, registry).flat_map(&:render)
        written = writer.write_all(files)

        @warnings = loader.warnings + registry.warnings
        written
      end

      private

      sig { params(document: Model::Document, registry: TypeRegistry).returns(T::Array[Emit::Emitter]) }
      def emitters(document, registry)
        [
          Emit::Types.new(document: document, registry: registry, config: @config),
          Emit::Operations.new(document: document, registry: registry, config: @config),
          Emit::Handlers.new(document: document, config: @config),
          Emit::Security.new(document: document, config: @config),
          Emit::Container.new(document: document, config: @config),
          Emit::Routes.new(document: document, config: @config),
          Emit::Controllers.new(document: document, registry: registry, config: @config)
        ]
      end
    end
  end
end
