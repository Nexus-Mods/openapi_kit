# frozen_string_literal: true

require_relative "lib/oapi/version"

Gem::Specification.new do |spec|
  spec.name     = "oapi"
  spec.version  = Oapi::VERSION
  spec.authors  = ["Jack Robertson"]
  spec.email    = ["jack.robertson@nexusmods.com"]

  spec.summary     = "Generate Sorbet-typed Rails server stubs from an OpenAPI 3 document."
  spec.description = "A spec-first code generator producing strict Sorbet interfaces bound " \
                     "to implementations via dry-container, with sealed response types and " \
                     "an extensible type registry."
  spec.homepage      = "https://github.com/Nexus-Mods/oapi"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"]       = spec.homepage

  spec.files = Dir[
    "exe/oapi",
    "lib/oapi.rb",
    "lib/oapi/*.rb",
    "lib/oapi/{ir,analyzer,types,emit}/**/*.rb",
    "lib/oapi/templates/**/*.erb",
    "LICENSE.txt",
    "README.md"
  ]
  spec.bindir      = "exe"
  spec.executables = ["oapi"]
  spec.require_paths = ["lib"]

  spec.add_dependency "oapi-runtime", Oapi::VERSION
  spec.add_dependency "openapi3_parser", "~> 0.10.0"
end
