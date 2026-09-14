# frozen_string_literal: true

source "https://rubygems.org"

gemspec name: "openapi_kit-codegen"
gemspec name: "openapi_kit"

gem "rake", "~> 13.0"

group :development, :test do
  gem "appraisal", "~> 2.5", require: false

  # activesupport 8.1 calls JSON.parse with options json 3.0 removed, so Rails' own
  # parameter parsing raises and every request spec sees an empty 400.
  gem "json", "~> 2.21"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.66", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "sorbet", "~> 0.5", require: false
end

gem "zeitwerk", "~> 2.8", groups: %i[development test]

gem "railties", groups: %i[development test]

gem "rack-test", "~> 2.2", groups: %i[development test]
