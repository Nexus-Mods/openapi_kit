# frozen_string_literal: true

require "open3"

RSpec.describe Oapi::Generator do
  describe "the server schema" do
    let(:result) { generate("server.yaml", modules: %w[Server], "container_prefix" => "v1") }

    it "writes a file per concern plus an entry point" do
      expect(result[:dir].glob("*.rb").map { |f| f.basename.to_s }.sort)
        .to eq(%w[api.rb container.rb handlers.rb operations.rb types.rb])
    end

    it "matches the golden files" do
      result[:dir].glob("*.rb").each do |file|
        expect(file.read).to eq(golden("server/#{file.basename}").read), file.basename.to_s
      end
    end

    it "gives each tag one interface and one container key" do
      expect(result[:dir].join("handlers.rb").read).to include("module Mods", "module System")
      expect(result[:dir].join("container.rb").read)
        .to include(%("v1.handlers.mods"), %("v1.handlers.system"))
    end

    it "hands the handler Rails' own request rather than a wrapper of oapi's" do
      expect(result[:dir].join("operations.rb").read).to include("const :http, ::ActionDispatch::Request")
    end
  end

  describe "the kitchen sink schema" do
    let(:result) { generate("kitchen_sink.yaml", modules: %w[KitchenSink]) }
    let(:types) { result[:dir].join("types.rb").read }

    it "marks every file as generated" do
      expect(result[:dir].glob("*.rb")).to all(satisfy { |f| f.read.start_with?("#{Oapi::MARKER}\n") })
      expect(types).to start_with("#{Oapi::MARKER}\n# typed: strict\n")
    end

    it "matches the golden file" do
      expect(types).to eq(golden("kitchen_sink/types.rb").read)
    end

    it "generates no operations for a components-only document" do
      expect(result[:dir].join("operations.rb").read).to include("module Operations")
      expect(result[:dir].join("handlers.rb").read).not_to include("interface!")
    end

    it "typechecks, and round trips every construct at runtime" do
      output, status = Open3.capture2e(
        "bundle", "exec", "ruby", "-Ilib", "spec/scripts/round_trip.rb", result[:dir].to_s
      )

      expect(output).to include("round trip ok"), output
      expect(status).to be_success
    end
  end

  describe "schemas it refuses to guess at" do
    it "names the cycle and how to break it" do
      expect { generate("cyclic.yaml") }.to raise_error(
        Oapi::SchemaError,
        /Book -> Author -> Book form a cycle.*Break the cycle by referring to one side by id/m
      )
    end
  end
end
