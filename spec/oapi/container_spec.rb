# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oapi::Container do
  let(:complete) do
    Class.new do
      include Dummy::V1::Handlers::Mods

      def list_mods(request:) = Dummy::V1::Operations::ListMods::Ok.new(body: [])
      def create_mod(request:) = raise
    end
  end

  let(:system_handler) do
    Class.new do
      include Dummy::V1::Handlers::System

      def get_health(request:) = raise
    end
  end

  def container(registrations)
    Class.new do
      define_method(:registrations) { registrations }

      def key?(key) = registrations.key?(key)

      def resolve(key)
        registrations.fetch(key) { raise KeyError, "nothing registered with the key #{key.inspect}" }
      end
    end.new
  end

  it "passes when every handler is registered and implements its interface" do
    expect do
      Dummy::V1::Container.verify!(
        container("v1.handlers.mods" => complete.new, "v1.handlers.system" => system_handler.new)
      )
    end.not_to raise_error
  end

  # The point of verify!: dry-container is untyped, so a missing or wrong registration
  # is otherwise only discovered when that endpoint is first requested.
  it "names every key that is not registered" do
    expect { Dummy::V1::Container.verify!(container({})) }.to raise_error(
      Oapi::ContainerError, /v1\.handlers\.mods is not registered.*v1\.handlers\.system is not registered/m
    )
  end

  it "names a handler that does not implement the interface it is registered for" do
    expect do
      Dummy::V1::Container.verify!(
        container("v1.handlers.mods" => Object.new, "v1.handlers.system" => system_handler.new)
      )
    end.to raise_error(
      Oapi::ContainerError, /v1\.handlers\.mods resolves to Object, which does not include Dummy::V1::Handlers::Mods/
    )
  end

  # Reporting a handler's own constructor failure as "not registered" sends whoever is
  # debugging it to the wrong file.
  it "lets an error raised while building a handler surface as itself" do
    exploding = Class.new do
      def key?(_key) = true
      def resolve(_key) = raise(NoMethodError, "undefined method `frobnicate!'")
    end.new

    expect { Dummy::V1::Container.verify!(exploding) }
      .to raise_error(NoMethodError, /frobnicate!/)
  end

  it "lists the keys the generated API expects" do
    expect(Dummy::V1::Container::HANDLERS.keys).to eq(["v1.handlers.mods", "v1.handlers.system"])
  end
end
