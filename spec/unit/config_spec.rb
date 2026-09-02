# frozen_string_literal: true

require "tmpdir"

RSpec.describe Oapi::Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  end

  def write(yaml)
    path = @dir.join("oapi.yml")
    path.write(yaml)
    path
  end

  it "resolves paths relative to the config file" do
    config = described_class.load(write(<<~YAML))
      spec: specs/api.yaml
      output: generated
      modules: [API, V3]
    YAML

    expect(config.spec).to eq(@dir.join("specs/api.yaml"))
    expect(config.output).to eq(@dir.join("generated"))
    expect(config.namespace).to eq("API::V3")
  end

  it "builds container keys from the prefix" do
    config = described_class.load(write(<<~YAML))
      spec: api.yaml
      output: out
      modules: [API]
      container_prefix: v3
    YAML

    expect(config.container_key("handlers", "mods")).to eq("v3.handlers.mods")
  end

  it "omits an empty prefix rather than emitting a leading dot" do
    config = described_class.load(write(<<~YAML))
      spec: api.yaml
      output: out
      modules: [API]
    YAML

    expect(config.container_key("handlers", "mods")).to eq("handlers.mods")
  end

  describe "options it refuses to guess at" do
    it "names the unknown option and lists the valid ones" do
      expect { described_class.load(write("spec: a\noutput: b\nmodules: [A]\nmodules_: x\n")) }
        .to raise_error(Oapi::ConfigError, /unknown option modules_\. Known options: spec, output/)
    end

    it "requires spec, output and modules" do
      expect { described_class.load(write("spec: a\noutput: b\n")) }
        .to raise_error(Oapi::ConfigError, /`modules` is required/)
    end

    it "rejects an empty modules list" do
      expect { described_class.load(write("spec: a\noutput: b\nmodules: []\n")) }
        .to raise_error(Oapi::ConfigError, /must name at least one namespace, e\.g\. \[API, V3\]/)
    end

    it "reports a missing file rather than crashing" do
      expect { described_class.load(@dir.join("nope.yml")) }
        .to raise_error(Oapi::ConfigError, /No such config file/)
    end
  end
end
