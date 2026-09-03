# frozen_string_literal: true

require "rails_helper"

# The typed boundary between oapi's interfaces and an application's objects. Sorbet
# checks completeness at the call site, so there is no boot-time verification to run.
RSpec.describe "a generated registry" do
  def handler(interface, method)
    Class.new do
      include interface
      define_method(method) { |request:| raise("not called #{request}") }
    end.new
  end

  def authenticator(interface)
    Class.new do
      include interface
      def authenticate(*) = nil
    end.new
  end

  def mods_handler = handler(Dummy::V1::Handlers::Mods, :list_mods)
  def system_handler = handler(Dummy::V1::Handlers::System, :get_health)

  def registry(**overrides)
    Dummy::V1::Registry.new(
      mods: -> { mods_handler },
      system: -> { system_handler },
      bearer_auth: -> { authenticator(Dummy::V1::Security::BearerAuth) },
      api_key_auth: -> { authenticator(Dummy::V1::Security::ApiKeyAuth) },
      **overrides
    )
  end

  it "builds nothing until a reader is called" do
    built = []
    subject = registry(mods: lambda do
      built << :mods
      mods_handler
    end)

    expect(built).to be_empty
    subject.mods
    expect(built).to eq([:mods])
  end

  it "builds each piece once" do
    built = 0
    subject = registry(mods: lambda do
      built += 1
      mods_handler
    end)

    3.times { subject.mods }

    expect(built).to eq(1)
  end

  describe "#swap" do
    it "replaces one piece and leaves the rest alone" do
      fake = mods_handler
      original = registry

      swapped = original.swap(mods: fake)

      expect(swapped.mods).to be(fake)
      expect(swapped.system).to be_a(Dummy::V1::Handlers::System)
      expect(original.mods).not_to be(fake)
    end

    it "does not build the pieces it carries over" do
      built = []
      subject = registry(system: lambda do
        built << :system
        system_handler
      end)

      subject.swap(mods: mods_handler)

      expect(built).to be_empty
    end
  end

  describe ".from" do
    it "resolves out of anything answering resolve, deferring each lookup" do
      resolved = []
      registrations = { "v1.handlers.mods" => mods_handler }
      container = Class.new do
        define_method(:resolve) do |key|
          resolved << key
          registrations.fetch(key)
        end
      end.new

      subject = Dummy::V1::Registry.from(container)

      expect(resolved).to be_empty
      subject.mods
      expect(resolved).to eq(["v1.handlers.mods"])
    end
  end
end
