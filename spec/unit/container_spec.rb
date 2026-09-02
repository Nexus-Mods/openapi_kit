# frozen_string_literal: true

require "tmpdir"
require "zeitwerk"

CONTAINED_DIR = Pathname.new(Dir.mktmpdir)
Oapi::Codegen::Generator.new(
  config: Oapi::Codegen::Config.from_hash(
    { "spec" => Pathname.new(__dir__).join("../fixtures/schemas/server.yaml").to_s,
      "output" => CONTAINED_DIR.join("generated").to_s,
      "modules" => %w[Contained], "container_prefix" => "v1" },
    base: Pathname.pwd
  )
).generate

CONTAINED_LOADER = Zeitwerk::Loader.new
CONTAINED_LOADER.push_dir(CONTAINED_DIR.join("generated").to_s)
CONTAINED_LOADER.setup
CONTAINED_LOADER.eager_load

RSpec.describe Oapi::Container do
  let(:complete) do
    Class.new do
      include Contained::Handlers::Mods

      def list_mods(request:) = Contained::Operations::ListMods::Ok.new(body: [])
      def create_mod(request:) = raise
    end
  end

  let(:system_handler) do
    Class.new do
      include Contained::Handlers::System

      def get_health(request:) = raise
    end
  end

  def container(registrations)
    Class.new do
      define_method(:registrations) { registrations }

      def resolve(key)
        registrations.fetch(key) { raise KeyError, "nothing registered with the key #{key.inspect}" }
      end
    end.new
  end

  it "passes when every handler is registered and implements its interface" do
    expect do
      Contained::Container.verify!(
        container("v1.handlers.mods" => complete.new, "v1.handlers.system" => system_handler.new)
      )
    end.not_to raise_error
  end

  # The point of verify!: dry-container is untyped, so a missing or wrong registration
  # is otherwise only discovered when that endpoint is first requested.
  it "names every key that is not registered" do
    expect { Contained::Container.verify!(container({})) }.to raise_error(
      Oapi::ContainerError, /v1\.handlers\.mods is not registered.*v1\.handlers\.system is not registered/m
    )
  end

  it "names a handler that does not implement the interface it is registered for" do
    expect do
      Contained::Container.verify!(
        container("v1.handlers.mods" => Object.new, "v1.handlers.system" => system_handler.new)
      )
    end.to raise_error(
      Oapi::ContainerError, /v1\.handlers\.mods resolves to Object, which does not include Contained::Handlers::Mods/
    )
  end

  it "lists the keys the generated API expects" do
    expect(Contained::Container::HANDLERS.keys).to eq(["v1.handlers.mods", "v1.handlers.system"])
  end
end
