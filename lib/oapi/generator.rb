# typed: strict
# frozen_string_literal: true

module Oapi
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
      registry = Types::Registry.for(document, @config)
      writer = Writer.new(output: @config.output)

      rendered = { "types.rb" => Emit::Types.new(document: document, registry: registry, config: @config).render }

      writer.clean!
      rendered.each { |name, contents| writer.write(name, contents) }
      @warnings = registry.warnings
      writer.written
    end
  end
end
