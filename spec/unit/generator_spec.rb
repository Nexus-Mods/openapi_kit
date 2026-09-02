# frozen_string_literal: true

require "open3"

RSpec.describe Oapi::Codegen::Generator do
  describe "the server schema" do
    let(:result) { generate("server.yaml", modules: %w[Server], "container_prefix" => "v1") }

    it "writes one file per constant, at the path the constant implies" do
      expect(relative_paths(result[:dir])).to eq(
        %w[
          server/codecs/mod.rb server/codecs/mod_status.rb server/codecs/new_mod.rb
          server/codecs/problem_details.rb server/container.rb
          server/handlers/mods.rb server/handlers/system.rb
          server/operations/create_mod.rb server/operations/get_health.rb
          server/operations/list_mods.rb
          server/types/mod.rb server/types/mod_status.rb server/types/new_mod.rb
          server/types/problem_details.rb
        ]
      )
    end

    it "matches the golden files" do
      relative_paths(result[:dir]).each do |path|
        expect(result[:dir].join(path).read).to eq(golden("server/#{path}").read), path
      end
    end

    it "gives each tag one interface file and one container key" do
      expect(result[:dir].join("server/handlers/mods.rb").read).to include("module Mods")
      expect(result[:dir].join("server/handlers/system.rb").read).to include("module System")
      expect(result[:dir].join("server/container.rb").read)
        .to include(%("v1.handlers.mods"), %("v1.handlers.system"))
    end

    it "hands the handler Rails' own request rather than a wrapper of oapi's" do
      expect(result[:dir].join("server/operations/list_mods.rb").read)
        .to include("const :http, ::ActionDispatch::Request")
    end
  end

  describe "the kitchen sink schema" do
    let(:result) { generate("kitchen_sink.yaml", modules: %w[KitchenSink]) }

    it "marks every file as generated" do
      expect(result[:dir].glob("**/*.rb"))
        .to all(satisfy { |f| f.read.start_with?("#{Oapi::Codegen::MARKER}\n") })
    end

    it "matches the golden files" do
      relative_paths(result[:dir]).each do |path|
        expect(result[:dir].join(path).read).to eq(golden("kitchen_sink/#{path}").read), path
      end
    end

    it "generates no operation or handler files for a components-only document" do
      expect(relative_paths(result[:dir]).grep(%r{/operations/|/handlers/})).to be_empty
    end

    it "typechecks, and round trips every construct at runtime" do
      output, status = Open3.capture2e(
        "bundle", "exec", "ruby", "-Ilib", "spec/scripts/round_trip.rb", result[:dir].to_s
      )

      expect(output).to include("round trip ok"), output
      expect(status).to be_success
    end
  end

  # One constant per file lets Zeitwerk autoload the other side of a cycle on
  # reference, so this no longer has to be rejected.
  describe "mutually recursive schemas" do
    it "generates a file for each side" do
      paths = relative_paths(generate("cyclic.yaml", modules: %w[Cyc])[:dir])

      expect(paths).to include("cyc/types/author.rb", "cyc/types/book.rb")
    end
  end
end
