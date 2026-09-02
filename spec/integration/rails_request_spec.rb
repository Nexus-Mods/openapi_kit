# frozen_string_literal: true

require "rack/test"
require "action_controller/railtie"

require "oapi/rails"

class DummyApp < Rails::Application
  config.root = Pathname.new(__dir__).join("../..")
  config.eager_load = false
  config.secret_key_base = "oapi-integration"
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear
  config.autoload_paths << Pathname.new(__dir__).join("../golden/server").to_s
end

DummyApp.initialize!

class ModsHandler
  include Server::Handlers::Mods

  def list_mods(request:)
    if request.query.page < 1
      return Server::Operations::ListMods::BadRequest.new(
        body: Server::Types::ProblemDetails.new(title: "bad page")
      )
    end

    Server::Operations::ListMods::Ok.new(
      body: [Server::Types::Mod.new(id: 1, name: "#{request.path.game_domain}:#{request.query.page}",
                                    status: Server::Types::ModStatus::Live)]
    )
  end

  def create_mod(request:)
    Server::Operations::CreateMod::Created.new(
      body: Server::Types::Mod.new(id: 2, name: request.body.name, status: nil)
    )
  end
end

class SystemHandler
  include Server::Handlers::System

  def get_health(request:) = Server::Operations::GetHealth::Ok.new
end

class DummyContainer
  def initialize(registrations)
    @registrations = registrations
  end

  def resolve(key) = @registrations.fetch(key) { raise KeyError, "nothing registered for #{key.inspect}" }
end

CONTAINER = DummyContainer.new(
  "v1.handlers.mods" => ModsHandler.new,
  "v1.handlers.system" => SystemHandler.new
)

class ApiBaseController
  rescue_from Oapi::DecodeError, with: :bad_request

  private

  def oapi_container = CONTAINER

  def bad_request(error)
    render json: { "error" => error.detail, "field" => error.json_pointer },
           status: :bad_request
  end
end

Server::Container.verify!(CONTAINER)

DummyApp.routes.draw { scope("/v1") { Server::Routes.draw(self) } }

# The generated code is loaded by Rails' own autoloader from spec/golden/server, so
# this exercises routing, parameter decoding, handler dispatch and response rendering
# through the real stack rather than a harness.
RSpec.describe "a generated API inside a Rails application" do
  include Rack::Test::Methods

  def app = DummyApp

  def parsed_body = JSON.parse(last_response.body)

  it "routes a path parameter and a defaulted query parameter to the handler" do
    get "/v1/games/skyrim/mods"

    expect(last_response.status).to eq(200)
    expect(parsed_body.first["name"]).to eq("skyrim:1")
    expect(parsed_body.first["status"]).to eq("live")
  end

  it "decodes a supplied query parameter" do
    get "/v1/games/oblivion/mods?page=4"

    expect(parsed_body.first["name"]).to eq("oblivion:4")
  end

  it "lets the handler choose a different sealed response variant" do
    get "/v1/games/skyrim/mods?page=0"

    expect(last_response.status).to eq(400)
    expect(last_response.headers["content-type"]).to include("application/problem+json")
    expect(parsed_body["title"]).to eq("bad page")
  end

  it "decodes a JSON request body" do
    post "/v1/games/skyrim/mods", { name: "Cool Mod" }.to_json, { "CONTENT_TYPE" => "application/json" }

    expect(last_response.status).to eq(201)
    expect(parsed_body["name"]).to eq("Cool Mod")
  end

  it "omits a property the handler left nil" do
    post "/v1/games/skyrim/mods", { name: "No Status" }.to_json, { "CONTENT_TYPE" => "application/json" }

    expect(parsed_body).not_to have_key("status")
  end

  it "returns an empty body for a response with no content" do
    get "/v1/health"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_empty
  end

  # oapi raises and takes no view on the error body; the application decides.
  it "raises a DecodeError the application handles however it likes" do
    get "/v1/games/skyrim/mods?page=banana"

    expect(last_response.status).to eq(400)
    expect(parsed_body["field"]).to eq("/page")
    expect(parsed_body["error"]).to include("expected an integer")
  end
end
