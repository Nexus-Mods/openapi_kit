# frozen_string_literal: true

RSpec.describe OpenAPIKit::Codegen::Naming do
  describe ".snake" do
    {
      "gameDomainName" => "game_domain_name",
      "HTTPSConnection" => "https_connection",
      "modID" => "mod_id",
      "mod-files" => "mod_files",
      "already_snake" => "already_snake",
      "Status418" => "status418",
      "v3Api" => "v3_api",
      "  spaced  out " => "spaced_out"
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(described_class.snake(input)).to eq(expected)
      end
    end
  end

  describe ".pascal" do
    {
      "get_mod" => "GetMod",
      "mod-files" => "ModFiles",
      "gameDomainName" => "GameDomainName",
      "HTTPSConnection" => "HttpsConnection"
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(described_class.pascal(input)).to eq(expected)
      end
    end
  end

  describe ".identifier" do
    it "suffixes Ruby keywords so they stay legible" do
      expect(described_class.identifier("class")).to eq(:class_)
      expect(described_class.identifier("end")).to eq(:end_)
    end

    # The list is frozen rather than reflected over, so the same document generates the
    # same names whether or not ActiveSupport is loaded in the generating process.
    it "suffixes names ActiveSupport adds to Object, however the generator was loaded" do
      expect(described_class.identifier("to_param")).to eq(:to_param_)
      expect(described_class.identifier("presence")).to eq(:presence_)
      expect(described_class.identifier("try")).to eq(:try_)
    end

    # T::Struct refuses a prop whose accessor would shadow an existing method, and a
    # spec is entitled to name a property `method` or `hash`.
    it "suffixes names already defined on Object" do
      expect(described_class.identifier("method")).to eq(:method_)
      expect(described_class.identifier("hash")).to eq(:hash_)
      expect(described_class.identifier("display")).to eq(:display_)
    end

    it "prefixes names starting with a digit" do
      expect(described_class.identifier("2fa")).to eq(:n2fa)
    end

    it "falls back for an empty name" do
      expect(described_class.identifier("")).to eq(:value)
    end
  end

  describe ".enum_member" do
    it "uses Sorbet's PascalCase convention, not SCREAMING_CASE" do
      expect(described_class.enum_member("under_moderation")).to eq("UnderModeration")
    end

    it "handles the kebab-case values real specs use" do
      expect(described_class.enum_member("vortex-download-visited")).to eq("VortexDownloadVisited")
    end

    it "guards values that are not valid constants on their own" do
      expect(described_class.enum_member(3)).to eq("Value3")
      expect(described_class.enum_member(-1)).to eq("ValueMinus1")
      expect(described_class.enum_member("2fa")).to eq("Value2fa")
      expect(described_class.enum_member("")).to eq("Value")
    end
  end
end
