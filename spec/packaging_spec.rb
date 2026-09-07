# frozen_string_literal: true

# Nothing in CI installs the built gems, so a stale files glob is invisible until a
# user runs `gem install`. These specs follow the requires from each entry point and
# assert every file it reaches is actually packaged.
RSpec.describe "packaging" do
  # A require path is not always its gem name, and some are stdlib.
  let(:gem_for_require) { { "action_dispatch" => "actionpack", "action_controller" => "actionpack" } }
  let(:stdlib) { %w[date time set json yaml pathname fileutils optparse stringio] }
  let(:root) { Pathname.new(__dir__).join("..") }

  def gemspec(name) = Gem::Specification.load(root.join("#{name}.gemspec").to_s)

  def required_files(entry, seen = Set.new)
    path = root.join("lib", "#{entry}.rb")
    return seen unless path.file?
    return seen unless seen.add?("lib/#{entry}.rb")

    path.read.scan(/^require "(oapi[^"]*)"/).flatten.each { |nested| required_files(nested, seen) }
    seen
  end

  def external_requires(files)
    requires = files.flat_map { |file| root.join(file).read.scan(%r{^require "([a-z][a-z0-9_/-]*)"}) }
    requires.flatten
            .reject { |name| name.start_with?("oapi") }
            .map { |name| gem_for_require.fetch(name, name.split("/").first) }
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

    expect(external_requires(required_files("oapi-runtime")) - declared - stdlib).to be_empty
  end
end
