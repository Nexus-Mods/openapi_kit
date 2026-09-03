# frozen_string_literal: true

require "tmpdir"

module GeneratorHelper
  FIXTURES = Pathname.new(__dir__).join("../fixtures/schemas")
  GOLDEN = Pathname.new(__dir__).join("../golden")

  def generate(fixture, modules: %w[Demo V1], **options)
    dir = Pathname.new(Dir.mktmpdir)
    @generated_dirs << dir
    config = Oapi::Codegen::Config.from_hash(
      { "spec" => FIXTURES.join(fixture).to_s, "output" => dir.join("generated").to_s,
        "modules" => modules, "controller_base" => "ApiBaseController",
        "principal" => "::SpecPrincipal" }.merge(options),
      base: dir
    )
    generator = Oapi::Codegen::Generator.new(config: config)
    generator.generate
    { dir: dir.join("generated"), warnings: generator.warnings }
  end

  def golden(name)
    GOLDEN.join(name)
  end

  # Drives the generator from an inline document and returns the generated sources
  # keyed by relative path, so behaviour is asserted on the product rather than on
  # the intermediate model.
  def scratch_dir
    Pathname.new(Dir.mktmpdir).tap { |dir| @generated_dirs << dir }
  end

  def generate_from(yaml, modules: %w[Api], **options)
    dir = scratch_dir
    dir.join("api.yaml").write(yaml)

    config = Oapi::Codegen::Config.from_hash(
      { "spec" => "api.yaml", "output" => "generated", "modules" => modules,
        "controller_base" => "ApiBaseController", "principal" => "::SpecPrincipal" }.merge(options),
      base: dir
    )
    generator = Oapi::Codegen::Generator.new(config: config)
    generator.generate

    output = dir.join("generated")
    sources = output.glob("**/*.rb").to_h { |file| [file.relative_path_from(output).to_s, file.read] }
    Generated.new(sources: sources, warnings: generator.warnings)
  end

  class Generated < T::Struct
    extend T::Sig

    const :sources, T::Hash[String, String]
    const :warnings, T::Array[String]

    sig { params(path: String).returns(String) }
    def [](path) = sources.fetch(path) { raise KeyError, "no #{path} in #{paths.inspect}" }

    sig { returns(T::Array[String]) }
    def paths = sources.keys.sort

    sig { params(name: String).returns(String) }
    def type(name) = self["api/types/#{name}.rb"]
  end

  def relative_paths(dir)
    dir.glob("**/*.rb").map { |file| file.relative_path_from(dir).to_s }.sort
  end
end

RSpec.configure do |config|
  config.include GeneratorHelper
  config.before { @generated_dirs = [] }
  config.after { @generated_dirs.each { |d| FileUtils.remove_entry(d) } }
end
