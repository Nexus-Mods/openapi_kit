# frozen_string_literal: true

require_relative "lib/openapi_kit/version"

Gem::Specification.new do |spec|
  spec.name     = "openapi_kit-codegen"
  spec.version  = OpenAPIKit::VERSION
  spec.authors  = ["Jack Robertson"]
  spec.email    = ["jack.robertson@nexusmods.com"]

  spec.summary     = "Generate Sorbet-typed Rails server stubs from an OpenAPI 3 document."
  spec.description = "A spec-first code generator producing strict Sorbet interfaces bound " \
                     "to implementations via dry-container, with sealed response types and " \
                     "an extensible type registry."
  spec.homepage      = "https://github.com/Nexus-Mods/openapi_kit"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"]       = spec.homepage

  spec.files = Dir[
    "exe/openapi_kit",
    "lib/openapi_kit-codegen.rb",
    "lib/openapi_kit/codegen.rb",
    "lib/openapi_kit/codegen/**/*.rb",
    "LICENSE.txt",
    "README.md"
  ]
  spec.bindir      = "exe"
  spec.executables = ["openapi_kit"]
  spec.require_paths = ["lib"]

  spec.add_dependency "openapi3_parser", "~> 0.10.0"
  spec.add_dependency "openapi_kit", OpenAPIKit::VERSION
  spec.add_dependency "prism", "~> 1.0"
end
