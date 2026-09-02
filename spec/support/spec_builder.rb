# frozen_string_literal: true

require "tmpdir"

module SpecBuilder
  def load_spec(yaml, files: {}, **config_options)
    dir = Pathname.new(Dir.mktmpdir)
    @spec_dirs << dir
    files.each do |name, contents|
      path = dir.join(name)
      path.dirname.mkpath
      path.write(contents)
    end
    dir.join("api.yaml").write(yaml)

    config = Oapi::Codegen::Config.from_hash(
      { "spec" => "api.yaml", "output" => "out", "modules" => ["API"] }.merge(config_options),
      base: dir
    )
    Oapi::Codegen::Loader.new(config: config).parse
  end

  def openapi(paths: nil, components: nil)
    document = +%(openapi: 3.0.3\ninfo: { title: Test, version: "1.0" }\n)
    document << (paths ? "paths:\n#{indent(paths, 2)}" : "paths: {}\n")
    document << "components:\n  schemas:\n#{indent(components, 4)}" if components
    document
  end

  def indent(yaml, columns)
    "#{yaml.to_s.split("\n").map { |line| line.empty? ? line : "#{" " * columns}#{line}" }.join("\n")}\n"
  end

  def type_named(document, name)
    document.types.find { |t| Oapi::Codegen::Ir::TypeDef.name_of(t) == name }
  end

  def property(object_def, name)
    object_def.properties.find { |p| p.name == name }
  end
end

RSpec.configure do |config|
  config.include SpecBuilder
  config.before { @spec_dirs = [] }
  config.after { @spec_dirs.each { |d| FileUtils.remove_entry(d) } }
end
