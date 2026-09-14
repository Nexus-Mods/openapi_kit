# frozen_string_literal: true

# Nothing in CI installs the built gems, so a stale files glob is invisible until a
# user runs `gem install`. These specs follow the requires from each entry point and
# assert every file it reaches is actually packaged.
RSpec.describe "packaging" do
  # A require path is not always its gem name, and some are stdlib.
  let(:gem_for_require) { { "action_dispatch" => "actionpack", "action_controller" => "actionpack" } }
  let(:stdlib) { %w[date time set json yaml pathname fileutils optparse stringio tempfile] }
  let(:root) { Pathname.new(__dir__).join("..") }

  def gemspec(name) = Gem::Specification.load(root.join("#{name}.gemspec").to_s)

  def required_files(entry, seen = Set.new)
    path = root.join("lib", "#{entry}.rb")
    return seen unless path.file?
    return seen unless seen.add?("lib/#{entry}.rb")

    path.read.scan(/^require "(openapi_kit[^"]*)"/).flatten.each { |nested| required_files(nested, seen) }
    seen
  end

  def external_requires(files)
    requires = files.flat_map { |file| root.join(file).read.scan(%r{^require "([a-z][a-z0-9_/-]*)"}) }
    requires.flatten
            .reject { |name| name.start_with?("openapi_kit") }
            .map { |name| gem_for_require.fetch(name, name.split("/").first) }
            .uniq
  end

  it "packages every file openapi_kit requires" do
    expect(required_files("openapi_kit") - gemspec("openapi_kit").files).to be_empty
  end

  it "packages every file the openapi_kit generator requires" do
    packaged = gemspec("openapi_kit-codegen").files + gemspec("openapi_kit").files

    expect(required_files("openapi_kit-codegen") - packaged).to be_empty
  end

  it "ships the generator's own sources, not just its entry point" do
    expect(gemspec("openapi_kit-codegen").files.grep(%r{lib/openapi_kit/codegen/}).size).to be > 10
  end

  it "keeps the runtime gem free of generator sources" do
    expect(gemspec("openapi_kit").files.grep(%r{lib/openapi_kit/codegen})).to be_empty
  end

  it "declares every gem the runtime actually requires" do
    declared = gemspec("openapi_kit").dependencies.map(&:name)

    expect(external_requires(required_files("openapi_kit")) - declared - stdlib).to be_empty
  end
end
