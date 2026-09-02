# frozen_string_literal: true

require "bundler/gem_helper"
require "rspec/core/rake_task"

Bundler::GemHelper.install_tasks(name: "oapi")

RSpec::Core::RakeTask.new(:spec)

desc "Typecheck with Sorbet"
task :typecheck do
  sh "bundle exec srb tc"
end

desc "Lint with RuboCop"
task :lint do
  sh "bundle exec rubocop"
end

task default: %i[spec typecheck lint]
