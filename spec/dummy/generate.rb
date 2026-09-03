# frozen_string_literal: true

require "oapi"

# The dummy application owns its generated code, the same as a real one: generated
# into app/api, which Rails autoloads with no further configuration.
module Dummy
  module Generate
    ROOT = Pathname.new(__dir__)

    def self.call
      config = Oapi::Codegen::Config.from_hash(
        {
          "spec" => ROOT.join("../fixtures/schemas/server.yaml").to_s,
          "output" => ROOT.join("app/api").to_s,
          "modules" => %w[Dummy V1],
          "controller_base" => "Dummy::BaseController",
          "container_prefix" => "v1",
          "principal" => "::Principal"
        },
        base: ROOT
      )

      Oapi::Codegen::Generator.new(config: config).generate
    end
  end
end
