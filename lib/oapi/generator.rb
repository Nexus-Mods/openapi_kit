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
      registry = TypeRegistry.for(document, @config)
      writer = Writer.new(output: @config.output)

      rendered = {
        "types.rb" => Emit::Types.new(document: document, registry: registry, config: @config).render,
        "operations.rb" => Emit::Operations.new(document: document, registry: registry, config: @config).render,
        "handlers.rb" => Emit::Handlers.new(document: document, config: @config).render,
        "container.rb" => Emit::Container.new(document: document, config: @config).render
      }

      writer.clean!
      rendered.each { |name, contents| writer.write(name, contents) }
      writer.write("api.rb", entry_point(rendered.keys))
      @warnings = registry.warnings
      writer.written
    end

    private

    sig { params(names: T::Array[String]).returns(String) }
    def entry_point(names)
      buffer = Emit::Buffer.new
      buffer.line("# typed: strict")
      buffer.line("# frozen_string_literal: true")
      buffer.blank
      buffer.line("require \"oapi-runtime\"")
      buffer.line("require \"oapi/rails\"")
      buffer.blank
      names.each { |name| buffer.line("require_relative #{name.delete_suffix(".rb").inspect}") }
      buffer.to_s
    end
  end
end
