# frozen_string_literal: true

require "bundler/gem_helper"
require "rspec/core/rake_task"

Bundler::GemHelper.install_tasks(name: "openapi_kit")

RSpec::Core::RakeTask.new(:spec)

desc "Typecheck with Sorbet"
task :typecheck do
  sh "bundle exec srb tc"
end

desc "Lint with RuboCop"
task :lint do
  sh "bundle exec rubocop"
end

desc "Regenerate the golden output and the dummy application's API"
task :golden do
  require "pathname"
  $LOAD_PATH.unshift("lib")
  require "openapi_kit-codegen"
  require_relative "spec/support/golden"
  require_relative "spec/dummy/generate"

  (Golden.call + Dummy::Generate.call).each { |path| puts path.relative_path_from(Pathname.pwd) }
end

task default: %i[spec typecheck lint]
