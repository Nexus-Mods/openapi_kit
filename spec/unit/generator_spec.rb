# frozen_string_literal: true

require "open3"

RSpec.describe Oapi::Generator do
  describe "the kitchen sink schema" do
    let(:result) { generate("kitchen_sink.yaml") }
    let(:types) { result[:dir].join("types.rb").read }

    it "writes one types file, marked as generated" do
      expect(result[:dir].glob("*.rb").map { |f| f.basename.to_s }).to eq(["types.rb"])
      expect(types).to start_with("#{Oapi::MARKER}\n# typed: strict\n")
    end

    it "matches the golden file" do
      expect(types).to eq(golden("kitchen_sink/types.rb").read)
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
