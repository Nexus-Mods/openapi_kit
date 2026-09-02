# frozen_string_literal: true

require "tmpdir"

module GeneratorHelper
  FIXTURES = Pathname.new(__dir__).join("../fixtures/schemas")
  GOLDEN = Pathname.new(__dir__).join("../golden")

  def generate(fixture, modules: %w[Demo V1], **options)
    dir = Pathname.new(Dir.mktmpdir)
    @generated_dirs << dir
    config = Oapi::Config.from_hash(
      { "spec" => FIXTURES.join(fixture).to_s, "output" => dir.join("generated").to_s,
        "modules" => modules }.merge(options),
      base: dir
    )
    generator = Oapi::Generator.new(config: config)
    generator.generate
    { dir: dir.join("generated"), warnings: generator.warnings }
  end

  def golden(name)
    GOLDEN.join(name)
  end
end

RSpec.configure do |config|
  config.include GeneratorHelper
  config.before { @generated_dirs = [] }
  config.after { @generated_dirs.each { |d| FileUtils.remove_entry(d) } }
end
