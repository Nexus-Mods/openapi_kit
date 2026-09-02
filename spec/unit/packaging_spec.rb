# frozen_string_literal: true

PACKAGING_ROOT = Pathname.new(__dir__).join("../..")
PACKAGING_GEM_FOR_REQUIRE = {
  "action_dispatch" => "actionpack", "action_controller" => "actionpack", "rails" => "railties"
}.freeze
PACKAGING_STDLIB = %w[date time set json yaml pathname fileutils optparse].freeze

# Nothing in CI installs the built gems, so a stale files glob is invisible until a
# user runs `gem install`. These specs follow the requires from each entry point and
# assert every file it reaches is actually packaged.
RSpec.describe "packaging" do
  def gemspec(name) = Gem::Specification.load(PACKAGING_ROOT.join("#{name}.gemspec").to_s)

  def required_files(entry, seen = Set.new)
    path = PACKAGING_ROOT.join("lib", "#{entry}.rb")
    return seen unless path.file?
    return seen unless seen.add?("lib/#{entry}.rb")

    path.read.scan(/^require "(oapi[^"]*)"/).flatten.each { |nested| required_files(nested, seen) }
    seen
  end

  def external_requires(files)
    requires = files.flat_map { |file| PACKAGING_ROOT.join(file).read.scan(%r{^require "([a-z][a-z0-9_/-]*)"}) }
    requires.flatten
            .reject { |name| name.start_with?("oapi") }
            .map { |name| PACKAGING_GEM_FOR_REQUIRE.fetch(name, name.split("/").first) }
            .uniq
  end

  it "packages every file oapi-runtime requires" do
    expect(required_files("oapi-runtime") - gemspec("oapi-runtime").files).to be_empty
  end

  it "packages every file the oapi generator requires" do
    packaged = gemspec("oapi").files + gemspec("oapi-runtime").files

    expect(required_files("oapi") - packaged).to be_empty
  end

  it "ships the generator's own sources, not just its entry point" do
    expect(gemspec("oapi").files.grep(%r{lib/oapi/codegen/}).size).to be > 10
  end

  it "keeps the runtime gem free of generator sources" do
    expect(gemspec("oapi-runtime").files.grep(%r{lib/oapi/codegen})).to be_empty
  end

  it "declares every gem the runtime actually requires" do
    declared = gemspec("oapi-runtime").dependencies.map(&:name)

    expect(external_requires(required_files("oapi-runtime")) - declared - PACKAGING_STDLIB).to be_empty
  end
end
