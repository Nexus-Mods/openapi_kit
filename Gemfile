# frozen_string_literal: true

source "https://rubygems.org"

gemspec name: "oapi"
gemspec name: "oapi-runtime"

gem "rake", "~> 13.0"

group :development, :test do
  gem "actionpack", "~> 8.0"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.66", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "sorbet", "~> 0.5", require: false
end

gem "zeitwerk", "~> 2.8", groups: %i[development test]

gem "railties", "~> 8.1", groups: %i[development test]
