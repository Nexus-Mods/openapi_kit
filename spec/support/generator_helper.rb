# frozen_string_literal: true

require "tmpdir"

module GeneratorHelper
  FIXTURES = Pathname.new(__dir__).join("../fixtures/schemas")
  GOLDEN = Pathname.new(__dir__).join("../golden")

  def generate(fixture, modules: %w[Demo V1], **options)
    dir = Pathname.new(Dir.mktmpdir)
    @generated_dirs << dir
    root = dir.join("generated")
    output = root.join(module_path(modules))
    config = config_for(spec: FIXTURES.join(fixture), output: output,
                        modules: modules, **options)
    generator = OpenAPIKit::Codegen::Generator.new(config: config)
    generator.generate
    { dir: output, root: root, warnings: generator.warnings }
  end

  def golden(name, modules)
    GOLDEN.join(name, module_path(modules))
  end

  # `output` is the exact directory now, so a caller that wants Zeitwerk to resolve the
  # namespace lays the path out to match it, the same way an application does.
  def module_path(modules) = modules.map { |name| OpenAPIKit::Codegen::Naming.snake(name) }.join("/")

  def config_for(spec:, output:, modules:, principal: "::SpecPrincipal", **options)
    OpenAPIKit::Codegen::Config.new(
      spec: spec, output: output, modules: modules,
      controller_base: "ApiBaseController", principal: principal, **options
    )
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

    config = config_for(spec: dir.join("api.yaml"),
                        output: dir.join("generated", module_path(modules)),
                        modules: modules, **options)
    generator = OpenAPIKit::Codegen::Generator.new(config: config)
    sources = generator.sources.to_h { |file| [file.path, file.contents] }

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
    def type(name) = self["types/#{name}.rb"]

    sig { params(name: String).returns(String) }
    def operation(name) = self["operations/#{name}.rb"]
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
