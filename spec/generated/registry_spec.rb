# frozen_string_literal: true

require "rails_helper"

# The typed boundary between oapi's interfaces and an application's objects, and the
# accessor a generated controller reads it from.
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

  # These two are what replaced the boot-time container check.
  it "refuses an implementation that does not satisfy its interface" do
    expect { registry(mods: Object.new) }
      .to raise_error(TypeError, /Can't set Dummy::V1::Registry.mods to/)
  end

  it "refuses a missing implementation" do
    expect { Dummy::V1::Registry.new(mods: handler(Dummy::V1::Handlers::Mods, :list_mods)) }
      .to raise_error(ArgumentError, /Missing required prop/)
  end

  it "is what a generated controller reads from" do
    expect(Dummy::V1.registry).to be_a(Dummy::V1::Registry)
    expect(Dummy::V1.registry.mods).to be_a(Dummy::V1::Handlers::Mods)
  end

  it "says what to do when nothing has been assigned" do
    original = Dummy::V1.registry
    Dummy::V1.instance_variable_set(:@registry, nil)

    expect { Dummy::V1.registry }
      .to raise_error(/Dummy::V1.registry has not been assigned.*Dummy::V1::Registry.new/m)
  ensure
    Dummy::V1.registry = original
  end
end
