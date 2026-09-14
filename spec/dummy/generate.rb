# frozen_string_literal: true

require "openapi_kit-codegen"

# The dummy application owns its generated code, the same as a real one: generated
# into app/api, which Rails autoloads with no further configuration.
module Dummy
  module Generate
    ROOT = Pathname.new(__dir__)

    def self.call
      config = OpenAPIKit::Codegen::Config.new(
        spec: ROOT.join("../fixtures/schemas/server.yaml").expand_path,
        output: ROOT.join("app/api/dummy/v1").expand_path,
        modules: %w[Dummy V1],
        controller_base: "Dummy::BaseController",
        principal: "::Principal"
      )

      OpenAPIKit::Codegen::Generator.new(config: config).generate
    end
  end
end
