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

  def eager(**overrides)
    Dummy::V1::Registry::Eager.new(
      mods: handler(Dummy::V1::Handlers::Mods, :list_mods),
      system: handler(Dummy::V1::Handlers::System, :get_health),
      bearer_auth: authenticator(Dummy::V1::Security::BearerAuth),
      api_key_auth: authenticator(Dummy::V1::Security::ApiKeyAuth),
      **overrides
    )
  end

  # This is what replaced the boot-time container check.
  it "refuses an implementation that does not satisfy the interface" do
    expect { eager(mods: Object.new) }
      .to raise_error(TypeError, /Can't set Dummy::V1::Registry::Eager.mods to/)
  end

  it "refuses a missing implementation" do
    expect { Dummy::V1::Registry::Eager.new(mods: handler(Dummy::V1::Handlers::Mods, :list_mods)) }
      .to raise_error(ArgumentError, /Missing required prop/)
  end

  it "is what a generated controller reads from" do
    expect(Dummy::V1::Registry.current).to be_a(Dummy::V1::Registry)
    expect(Dummy::V1::Registry.current.mods).to be_a(Dummy::V1::Handlers::Mods)
  end

  # An application may implement the interface itself, which is the seam: the readers are
  # plain signatures, so a struct's props satisfy them and a class may compute them.
  it "accepts any implementation of the interface" do
    computed = Class.new do
      include Dummy::V1::Registry

      def mods = @mods ||= ModsHandler.new
    end.new

    expect(computed.mods).to be_a(Dummy::V1::Handlers::Mods)
    expect { computed.system }.to raise_error(NotImplementedError, /must provide system/)
  end
end
