# typed: strict
# frozen_string_literal: true

module OpenAPIKit
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

      sig { returns(T::Array[Emit::SourceFile]) }
      def sources
        loader = Loader.new(config: @config)
        document = loader.parse
        registry = TypeRegistry.for(document, @config)

        files = emitters(document, registry).flat_map(&:render)
        @warnings = loader.warnings + registry.warnings
        files
      end

      sig { returns(T::Array[Pathname]) }
      def generate = Writer.new(output: @config.output).write_all(sources)

      private

      sig { params(document: Model::Document, registry: TypeRegistry).returns(T::Array[Emit::Emitter]) }
      def emitters(document, registry)
        [
          Emit::Types.new(document: document, registry: registry, config: @config),
          Emit::Operations.new(document: document, registry: registry, config: @config),
          Emit::Handlers.new(document: document, config: @config),
          Emit::Security.new(document: document, config: @config),
          Emit::Registry.new(document: document, config: @config),
          Emit::Routes.new(document: document, config: @config),
          Emit::Controllers.new(document: document, registry: registry, config: @config)
        ]
      end
    end
  end
end
