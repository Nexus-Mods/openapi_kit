# frozen_string_literal: true

require "rails_helper"

# Generated code loaded by Rails' own autoloader out of the dummy application's
# app/api, so routing, parameter decoding, handler dispatch and rendering all run
# through the real stack.
RSpec.describe "a generated API inside a Rails application" do
  def app = Dummy::Application

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
