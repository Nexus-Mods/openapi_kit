# frozen_string_literal: true

require "rails_helper"

# The typed boundary between oapi's interfaces and an application's objects. This is what
# replaced the boot-time container check: Sorbet does it at the call site, and
# sorbet-runtime does it too for an application that is not typed.
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

  def registry(**overrides)
    Dummy::V1::Registry.new(
      mods: handler(Dummy::V1::Handlers::Mods, :list_mods),
      system: handler(Dummy::V1::Handlers::System, :get_health),
      bearer_auth: authenticator(Dummy::V1::Security::BearerAuth),
      api_key_auth: authenticator(Dummy::V1::Security::ApiKeyAuth),
      **overrides
    )
  end

  it "accepts implementations that satisfy their interfaces" do
    expect(registry.mods).to be_a(Dummy::V1::Handlers::Mods)
    expect(registry.bearer_auth).to be_a(Dummy::V1::Security::BearerAuth)
  end

  it "refuses an implementation that does not satisfy the interface" do
    expect { registry(mods: Object.new) }
      .to raise_error(TypeError, /Can't set Dummy::V1::Registry.mods to/)
  end

  it "refuses a missing implementation" do
    expect { Dummy::V1::Registry.new(mods: handler(Dummy::V1::Handlers::Mods, :list_mods)) }
      .to raise_error(ArgumentError, /Missing required prop/)
  end
end
