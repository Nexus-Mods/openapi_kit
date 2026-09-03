# frozen_string_literal: true

require "rails_helper"

# The typed boundary between oapi's interfaces and an application's objects.
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
      mods: mods_handler,
      system: system_handler,
      bearer_auth: authenticator(Dummy::V1::Security::BearerAuth),
      api_key_auth: authenticator(Dummy::V1::Security::ApiKeyAuth),
      **overrides
    )
  end

  # This is what replaced the boot-time container check: the type system does it, and
  # sorbet-runtime does it too for an application that is not typed.
  it "refuses an implementation that does not satisfy the interface" do
    expect { registry(mods: Object.new) }
      .to raise_error(TypeError, /Can't set Dummy::V1::Registry.mods to/)
  end

  it "refuses a missing implementation" do
    expect { Dummy::V1::Registry.new(mods: mods_handler) }
      .to raise_error(ArgumentError, /Missing required prop/)
  end

  describe "#swap" do
    it "replaces one piece and carries the rest over" do
      fake = mods_handler
      original = registry

      swapped = original.swap(mods: fake)

      expect(swapped.mods).to be(fake)
      expect(swapped.system).to be(original.system)
      expect(original.mods).not_to be(fake)
    end

    it "refuses a replacement that does not satisfy the interface" do
      expect { registry.swap(mods: Object.new) }.to raise_error(TypeError)
    end
  end
end
