# frozen_string_literal: true

require "open3"

RSpec.describe OpenAPIKit::Codegen::Generator do
  describe "the server schema" do
    let(:result) { generate("server.yaml", modules: %w[Server], **Golden::FIXTURES.fetch("server")) }

    it "writes one file per constant, at the path the constant implies" do
      expect(relative_paths(result[:dir])).to eq(
        %w[
          controllers/files_controller.rb controllers/mods_controller.rb
          controllers/system_controller.rb
          handlers/files.rb handlers/mods.rb handlers/system.rb
          operations/create_mod.rb operations/download_mod_file.rb operations/get_health.rb
          operations/list_mods.rb operations/upload_mod_file.rb
          registry.rb routes.rb security.rb
          types/mod.rb types/mod_status.rb types/new_mod.rb
          types/problem_details.rb types/upload_mod_file_body.rb
        ]
      )
    end

    it "matches the golden files" do
      relative_paths(result[:dir]).each do |path|
        expect(result[:dir].join(path).read).to eq(golden("server", %w[Server]).join(path).read), path
      end
    end

    it "gives each tag one interface file and one registry slot" do
      expect(result[:dir].join("handlers/mods.rb").read).to include("module Mods")
      expect(result[:dir].join("handlers/system.rb").read).to include("module System")
      expect(result[:dir].join("registry.rb").read)
        .to include("const :mods, Server::Handlers::Mods",
                    "const :system, Server::Handlers::System")
    end

    it "hands the handler Rails' own request rather than a wrapper of openapi_kit's" do
      expect(result[:dir].join("operations/list_mods.rb").read)
        .to include("const :http_request, ::ActionDispatch::Request")
    end
  end

  describe "the kitchen sink schema" do
    let(:result) { generate("kitchen_sink.yaml", modules: %w[KitchenSink]) }

    it "marks every file as generated" do
      expect(result[:dir].glob("**/*.rb"))
        .to all(satisfy { |f| f.read.start_with?("#{OpenAPIKit::Codegen::MARKER}\n") })
    end

    it "matches the golden files" do
      relative_paths(result[:dir]).each do |path|
        expect(result[:dir].join(path).read).to eq(golden("kitchen_sink", %w[KitchenSink]).join(path).read), path
      end
    end

    it "generates no operation or handler files for a components-only document" do
      expect(relative_paths(result[:dir]).grep(%r{\Aoperations/|\Ahandlers/})).to be_empty
    end

    it "typechecks, and round trips every construct at runtime" do
      output, status = Open3.capture2e(
        "bundle", "exec", "ruby", "-Ilib", "spec/scripts/round_trip.rb", result[:root].to_s
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

      expect(paths).to include("types/author.rb", "types/book.rb")
    end
  end
end
