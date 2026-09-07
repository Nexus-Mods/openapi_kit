# frozen_string_literal: true

require "tmpdir"

RSpec.describe Oapi::Codegen::Config do
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
    config = described_class.from_file(write(<<~YAML))
      spec: specs/api.yaml
      output: generated
      modules: [API, V3]
      controller_base: ApiBaseController
    YAML

    expect(config.spec).to eq(@dir.join("specs/api.yaml"))
    expect(config.output).to eq(@dir.join("generated"))
    expect(config.namespace).to eq("API::V3")
  end

  it "builds container keys from the prefix" do
    config = described_class.from_file(write(<<~YAML))
      spec: api.yaml
      output: out
      modules: [Api]
      controller_base: ApiBaseController
      container_prefix: v3
    YAML

    expect(config.container_key("handlers", "mods")).to eq("v3.handlers.mods")
  end

  it "omits an absent prefix rather than emitting a leading dot" do
    config = described_class.from_file(write(<<~YAML))
      spec: api.yaml
      output: out
      modules: [Api]
      controller_base: ApiBaseController
    YAML

    expect(config.container_key("handlers", "mods")).to eq("handlers.mods")
  end

  describe "type mappings" do
    def with_mapping(body)
      described_class.from_file(write(<<~YAML))
        spec: openapi/api.yaml
        output: app/api
        modules: [Api]
        controller_base: Base
        type_mappings:
          "string:money":
        #{body.lines.map { |line| "    #{line}" }.join.rstrip}
      YAML
    end

    it "parses a type and codec into a RubyType" do
      config = with_mapping("type: \"::Money\"\ncodec: MyApp::MoneyCodec\n")

      expect(config.type_mappings.fetch("string:money"))
        .to have_attributes(type: "::Money", codec: "MyApp::MoneyCodec")
    end

    it "names the mapping that is not a mapping" do
      expect { with_mapping("\"::Money\"\n") }
        .to raise_error(Oapi::ConfigError, /type_mappings\["string:money"\] must be a mapping/)
    end

    it "names an unknown key, and lists the valid ones" do
      expect { with_mapping("type: \"::Money\"\ncodec: C\nformat: money\n") }
        .to raise_error(Oapi::ConfigError, /has unknown key format\. Valid keys: type, codec/)
    end

    it "says which half is missing" do
      expect { with_mapping("type: \"::Money\"\n") }
        .to raise_error(Oapi::ConfigError, /is missing codec\. Both are required/)
    end

    it "refuses a codec that is not a constant path" do
      expect { with_mapping("type: \"::Money\"\ncodec: money_codec\n") }
        .to raise_error(Oapi::ConfigError, /is "money_codec", which is not a Ruby constant path/)
    end
  end

  describe "options it refuses to guess at" do
    it "names the unknown option and lists the valid ones" do
      expect { described_class.from_file(write("spec: a\noutput: b\nmodules: [A]\ncontroller_base: C\nmodules_: x\n")) }
        .to raise_error(Oapi::ConfigError, /unknown option modules_\. Known options: spec, output/)
    end

    it "requires spec, output and modules" do
      expect { described_class.from_file(write("spec: a\noutput: b\n")) }
        .to raise_error(Oapi::ConfigError, /`modules` is required/)
    end

    it "rejects an empty modules list" do
      expect { described_class.from_file(write("spec: a\noutput: b\nmodules: []\ncontroller_base: C\n")) }
        .to raise_error(Oapi::ConfigError, /must name at least one namespace, e\.g\. \[API, V3\]/)
    end

    it "reports a missing file rather than crashing" do
      expect { described_class.from_file(@dir.join("nope.yml")) }
        .to raise_error(Oapi::ConfigError, /No such config file/)
    end
  end
end
