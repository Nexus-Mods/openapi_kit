# frozen_string_literal: true

require "rails_helper"

# Generated code loaded by Rails' own autoloader out of the dummy application's
# app/api, so routing, parameter decoding, handler dispatch and rendering all run
# through the real stack.
RSpec.describe "a generated API inside a Rails application", type: :request do
  def app = Dummy::Application

  def parsed_body = JSON.parse(last_response.body)

  # The document puts every operation but /health behind bearerAuth.
  def bearer(scopes: []) = { "HTTP_AUTHORIZATION" => "Bearer t0ken", "HTTP_X_SCOPES" => scopes.join(",") }

  it "routes a path parameter and a defaulted query parameter to the handler" do
    get "/v1/games/skyrim/mods", {}, bearer

    expect(last_response.status).to eq(200)
    expect(parsed_body.first["name"]).to eq("skyrim:1")
    expect(parsed_body.first["status"]).to eq("live")
  end

  it "decodes a supplied query parameter" do
    get "/v1/games/oblivion/mods?page=4", {}, bearer

    expect(parsed_body.first["name"]).to eq("oblivion:4")
  end

  it "lets the handler choose a different sealed response variant" do
    get "/v1/games/skyrim/mods?page=0", {}, bearer

    expect(last_response.status).to eq(400)
    expect(last_response.headers["content-type"]).to include("application/problem+json")
    expect(parsed_body["title"]).to eq("bad page")
  end

  it "decodes a JSON request body" do
    post "/v1/games/skyrim/mods", { name: "Cool Mod" }.to_json,
         { "CONTENT_TYPE" => "application/json" }.merge(bearer(scopes: ["mods:write"]))

    expect(last_response.status).to eq(201)
    expect(parsed_body["name"]).to start_with("Cool Mod")
  end

  it "omits a property the handler left nil" do
    post "/v1/games/skyrim/mods", { name: "No Status" }.to_json,
         { "CONTENT_TYPE" => "application/json" }.merge(bearer(scopes: ["mods:write"]))

    expect(parsed_body).not_to have_key("status")
  end

  it "returns an empty body for a response with no content" do
    get "/v1/health"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_empty
  end

  # oapi reports what the document requires and the application does the checking, so
  # these assert the wiring rather than any particular auth scheme.
  describe "security" do
    it "refuses an operation the document protects when no credential is sent" do
      get "/v1/games/skyrim/mods"

      expect(last_response.status).to eq(401)
    end

    it "lets an operation through when the requirement is satisfied" do
      get "/v1/games/skyrim/mods", {}, bearer

      expect(last_response.status).to eq(200)
    end

    it "enforces the scopes the operation asks for" do
      post "/v1/games/skyrim/mods", { name: "Cool Mod" }.to_json,
           { "CONTENT_TYPE" => "application/json" }.merge(bearer)

      expect(last_response.status).to eq(401)
    end

    it "accepts the second alternative when the first is not satisfied" do
      post "/v1/games/skyrim/mods", { name: "Cool Mod" }.to_json,
           { "CONTENT_TYPE" => "application/json", "HTTP_X_API_KEY" => "k3y" }

      expect(last_response.status).to eq(201)
    end

    it "hands the handler the principal the authenticator produced" do
      get "/v1/games/skyrim/mods", {}, bearer

      expect(parsed_body.first["id"]).to eq("t0ken".hash.abs % 1000)
    end

    it "hands the handler whichever alternative authenticated" do
      post "/v1/games/skyrim/mods", { name: "Cool Mod" }.to_json,
           { "CONTENT_TYPE" => "application/json", "HTTP_X_API_KEY" => "k3y" }

      expect(parsed_body["name"]).to eq("Cool Mod by robot-k3y")
    end

    it "leaves an operation that opts out of security alone" do
      get "/v1/health"

      expect(last_response.status).to eq(200)
    end
  end

  describe "files" do
    def upload(name: "mod.zip", body: "PK\x03\x04binary", description: nil)
      params = { "upload" => Rack::Test::UploadedFile.new(StringIO.new(body), "application/zip",
                                                          original_filename: name) }
      params["description"] = description unless description.nil?

      put "/v1/games/skyrim/mods/7/file", params
    end

    it "decodes a multipart upload into the file Rails parsed" do
      upload(description: "a mod")

      expect(last_response.status).to eq(204)
      expect(last_response.body).to be_empty
    end

    it "streams a binary response body back as the bytes the handler wrote" do
      upload(name: "cool.zip", body: "the actual bytes", description: "a mod")

      get "/v1/games/skyrim/mods/7/file"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to eq("application/octet-stream")
      expect(last_response.body).to eq("cool.zip|a mod|the actual bytes")
    end

    it "sends a file body through the server, which may copy it itself" do
      Tempfile.create("download") do |file|
        file.write("the actual bytes")
        file.flush
        FilesHandler::STORE[8] = Oapi::Body::File.new(path: Pathname.new(file.path))

        get "/v1/games/skyrim/mods/8/file"

        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-length"]).to eq("16")
        expect(last_response.body).to eq("the actual bytes")
      end
    end

    it "renders a JSON variant of the same operation as JSON" do
      get "/v1/games/skyrim/mods/404/file"

      expect(last_response.status).to eq(404)
      expect(last_response.headers["content-type"]).to include("application/problem+json")
      expect(parsed_body["title"]).to eq("no file for mod 404")
    end

    it "refuses a multipart body whose file field is not a file" do
      put "/v1/games/skyrim/mods/7/file", { "upload" => "not-a-file" }

      expect(last_response.status).to eq(400)
      expect(parsed_body["field"]).to eq("/upload")
      expect(parsed_body["error"]).to include("expected an uploaded file")
    end
  end

  # oapi raises and takes no view on the error body; the application decides.
  it "raises a DecodeError the application handles however it likes" do
    get "/v1/games/skyrim/mods?page=banana", {}, bearer

    expect(last_response.status).to eq(400)
    expect(parsed_body["field"]).to eq("/page")
    expect(parsed_body["error"]).to include("expected an integer")
  end
end
