# frozen_string_literal: true

# What the generator makes of a document, asserted on the generated sources rather
# than on the model in between.
RSpec.describe "translating a document" do
  def document(*lines) = generate_from(lines.join("\n"))

  def schemas(body)
    document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths: {}",
             "components:", "  schemas:", *indent(body, 4))
  end

  def indent(body, columns) = body.strip.lines.map { |line| "#{" " * columns}#{line.chomp}" }

  def multi_file_document
    dir = scratch_dir
    dir.join("shared.yaml").write(<<~YAML)
      openapi: 3.0.3
      info: { title: S, version: "1.0" }
      paths: {}
      components:
        schemas:
          ProblemDetails: { type: object, properties: { title: { type: string } } }
    YAML
    dir.join("api.yaml").write(<<~YAML)
      openapi: 3.0.3
      info: { title: T, version: "1.0" }
      paths: {}
      components:
        schemas:
          Mod:
            type: object
            properties:
              error: { $ref: "shared.yaml#/components/schemas/ProblemDetails" }
    YAML
    config = OpenAPIKit::Codegen::Config.new(
      spec: dir.join("api.yaml"), output: dir.join("generated"),
      modules: %w[Api], controller_base: "ApiBaseController"
    )
    OpenAPIKit::Codegen::Generator.new(config: config).generate
    dir
  end

  describe "shapes the previous generator mistyped" do
    it "hoists an inline object property into its own type" do
      generated = schemas(<<~YAML)
        Mod:
          type: object
          properties:
            meta: { type: object, properties: { note: { type: string } } }
      YAML

      expect(generated.paths).to include("api/types/mod_meta.rb")
      expect(generated.type("mod")).to include("const :meta, T.nilable(Api::Types::ModMeta)")
    end

    it "hoists an inline enum into a T::Enum" do
      generated = schemas(<<~YAML)
        Mod:
          type: object
          properties:
            status: { type: string, enum: [live, under-moderation] }
      YAML

      expect(generated.type("mod_status")).to include("class ModStatus < T::Enum",
                                                      %(Live = new("live")),
                                                      %(UnderModeration = new("under-moderation")))
    end

    it "keeps the format of array items" do
      generated = schemas(<<~YAML)
        Mod:
          type: object
          properties:
            dates: { type: array, items: { type: string, format: date-time } }
      YAML

      expect(generated.type("mod")).to include("const :dates, T.nilable(T::Array[::Time])")
    end
  end

  describe "composition" do
    it "flattens allOf and unions the required sets" do
      generated = schemas(<<~YAML)
        Base: { type: object, required: [id], properties: { id: { type: integer } } }
        Mod:
          allOf:
            - $ref: "#/components/schemas/Base"
            - type: object
              required: [name]
              properties: { name: { type: string } }
      YAML

      expect(generated.type("mod")).to include("const :id, ::Integer", "const :name, ::String")
    end

    it "keeps a default declared beside an allOf ref" do
      generated = schemas(<<~YAML)
        Status: { type: string, enum: [live, hidden] }
        Mod:
          type: object
          properties:
            status:
              description: current status
              default: live
              allOf: [{ $ref: "#/components/schemas/Status" }]
      YAML

      expect(generated.type("mod"))
        .to include("const :status, Api::Types::Status, factory: -> { Api::Types::Status::Codec.from_wire(\"live\") }")
    end

    it "unwraps the nullable-allOf-ref idiom" do
      generated = schemas(<<~YAML)
        User: { type: object, properties: { name: { type: string } } }
        Mod:
          type: object
          properties:
            owner:
              nullable: true
              allOf: [{ $ref: "#/components/schemas/User" }]
      YAML

      expect(generated.type("mod"))
        .to include("const :owner, ::OpenAPIKit::Optional[T.nilable(Api::Types::User)]")
    end

    it "dispatches a discriminated union on the wire value, not the Ruby constant" do
      generated = schemas(<<~YAML)
        cat_thing: { type: object, required: [kind], properties: { kind: { type: string } } }
        dog_thing: { type: object, required: [kind], properties: { kind: { type: string } } }
        Pet:
          oneOf: [{ $ref: "#/components/schemas/cat_thing" }, { $ref: "#/components/schemas/dog_thing" }]
          discriminator: { propertyName: kind }
      YAML

      expect(generated.type("pet")).to include(%(when "cat_thing"), %(when "dog_thing"))
    end

    it "tries each member of an untagged union in turn" do
      generated = schemas("Loose: { anyOf: [{ type: string }, { type: integer }] }")

      expect(generated.type("loose")).to include("Value = T.type_alias { T.any(::String, ::Integer) }",
                                                 "::OpenAPIKit::Decode.first_of")
    end

    it "lets a schema refer to itself, suffixing a property named after a keyword" do
      generated = schemas(<<~YAML)
        Node:
          type: object
          properties:
            next: { $ref: "#/components/schemas/Node" }
      YAML

      expect(generated.type("node")).to include("const :next_, T.nilable(Api::Types::Node)")
    end

    it "follows a ref into another file" do
      dir = multi_file_document

      expect(dir.join("generated/api/types/problem_details.rb")).to exist
    end
  end

  describe "types and formats" do
    def property(schema) = schemas("Mod: { type: object, required: [it], properties: { it: #{schema} } }")

    {
      "{ type: string }" => "::String",
      "{ type: string, format: date-time }" => "::Time",
      "{ type: string, format: date }" => "::Date",
      "{ type: string, format: uuid }" => "::String",
      "{ type: integer, format: int64 }" => "::Integer",
      "{ type: number, format: decimal }" => "::BigDecimal",
      "{ type: boolean }" => "T::Boolean",
      "{ type: object, additionalProperties: { type: integer } }" => "T::Hash[::String, ::Integer]"
    }.each do |schema, expected|
      it "renders #{schema} as #{expected}" do
        expect(property(schema).type("mod")).to include("const :it, #{expected}")
      end
    end

    # multipleOf is any positive number in OpenAPI, including on an integer schema.
    it "accepts a fractional multipleOf on an integer schema" do
      generated = schemas("Mod: { type: object, properties: { n: { type: integer, multipleOf: 0.5 } } }")

      expect(generated.type("mod")).to include("const :n, T.nilable(::Integer)")
    end

    # A file has no JSON representation, so binary is refused anywhere it could not
    # produce one, rather than generating a decode that can never succeed.
    it "refuses format: binary in a response, however deeply nested" do
      expect do
        document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                 "  /f:", "    get:", "      operationId: getFile", "      tags: [files]",
                 "      responses:", %(        "200":), "          description: ok",
                 "          content:", "            application/json:",
                 "              schema:", "                type: array",
                 "                items:", "                  type: object",
                 "                  properties: { blob: { type: string, format: binary } }")
      end.to raise_error(OpenAPIKit::SchemaError, /the Ok response of getFile declares format: binary/)
    end

    it "refuses format: binary in a JSON request body" do
      expect do
        document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                 "  /f:", "    post:", "      operationId: postFile", "      tags: [files]",
                 "      requestBody:", "        content:", "          application/json:",
                 "            schema:", "              type: object",
                 "              properties: { upload: { type: string, format: binary } }",
                 %(      responses: { "204": { description: done } }))
      end.to raise_error(OpenAPIKit::SchemaError, /the request body of postFile declares format: binary/)
    end

    it "refuses format: binary in a parameter" do
      expect do
        document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                 "  /f:", "    get:", "      operationId: getFile", "      tags: [files]",
                 "      parameters:",
                 "        - { name: blob, in: query, schema: { type: string, format: binary } }",
                 %(      responses: { "204": { description: done } }))
      end.to raise_error(OpenAPIKit::SchemaError, /parameter "blob" of getFile declares format: binary/)
    end

    it "accepts format: binary as a property of a multipart request body" do
      generated = document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                           "  /f:", "    post:", "      operationId: postFile", "      tags: [files]",
                           "      requestBody:", "        content:", "          multipart/form-data:",
                           "            schema:", "              type: object",
                           "              required: [upload]",
                           "              properties: { upload: { type: string, format: binary } }",
                           %(      responses: { "204": { description: done } }))

      expect(generated.warnings).to be_empty
      expect(generated.type("post_file_body")).to include(
        "const :upload, ::ActionDispatch::Http::UploadedFile",
        "module Form",
        "sig { override.params(parts: ::OpenAPIKit::Form::Parts).returns(Api::Types::PostFileBody) }",
        %(upload: ::OpenAPIKit::Decode.required(parts, "upload") { |v| ::OpenAPIKit::Decode.file(v) })
      )
      expect(generated["api/controllers/files_controller.rb"]).to include(
        "Api::Types::PostFileBody::Form.from_parts(request.request_parameters)"
      )
    end

    def multipart_component(properties)
      <<~YAML
        openapi: 3.0.3
        info: { title: T, version: "1.0" }
        paths:
          /f:
            post:
              operationId: postFields
              tags: [files]
              requestBody:
                content:
                  multipart/form-data:
                    schema: { $ref: "#/components/schemas/Fields" }
              responses: { "204": { description: done } }
        components:
          schemas:
            Fields:
              type: object
              required: [#{properties.keys.first}]
              properties: { #{properties.map { |name, schema| "#{name}: #{schema}" }.join(", ")} }
      YAML
    end

    # A file may live in a component: it becomes a form type, decoded but never encoded.
    it "gives a referenced component holding a file a from_form and no codec" do
      generated = generate_from(multipart_component("upload" => "{ type: string, format: binary }"))

      expect(generated.type("fields")).to include("module Form", "def self.from_parts(parts)")
      expect(generated.type("fields")).not_to include("module Codec")
    end

    # Without a file it is an ordinary type, so it keeps its codec and decodes through it,
    # exactly as an urlencoded body of the same shape would.
    it "leaves a referenced component without a file on the codec path" do
      generated = generate_from(multipart_component("name" => "{ type: string }"))

      expect(generated.type("fields")).to include("module Codec", "def self.to_wire(value)")
      expect(generated["api/controllers/files_controller.rb"]).to include(
        "Api::Types::Fields::Codec.from_wire(request.request_parameters)"
      )
    end

    it "refuses a multipart body that is not an object" do
      expect do
        document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                 "  /f:", "    post:", "      operationId: postFile", "      tags: [files]",
                 "      requestBody:", "        content:", "          multipart/form-data:",
                 "            schema: { type: string }",
                 %(      responses: { "204": { description: done } }))
      end.to raise_error(OpenAPIKit::SchemaError, /is not an object/)
    end

    it "decodes the extra fields of a multipart body that allows them" do
      generated = document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                           "  /f:", "    post:", "      operationId: postFile", "      tags: [files]",
                           "      requestBody:", "        content:", "          multipart/form-data:",
                           "            schema:", "              type: object",
                           "              properties: { upload: { type: string, format: binary } }",
                           "              additionalProperties: { type: string }",
                           %(      responses: { "204": { description: done } }))

      expect(generated.type("post_file_body")).to include(
        %(additional_properties: ::OpenAPIKit::Decode.values(parts.except("upload")))
      )
    end

    it "accepts format: binary as a whole response body, with any media type" do
      generated = document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                           "  /f:", "    get:", "      operationId: getFile", "      tags: [files]",
                           "      responses:", %(        "200":), "          description: ok",
                           "          content:", "            image/png:",
                           "              schema: { type: string, format: binary }")

      expect(generated.operation("get_file")).to include(
        "const :body, ::OpenAPIKit::Body::Binary",
        "def to_body = body",
        %(def content_type = "image/png")
      )
    end

    it "falls back to the base type for an unrecognised format, and says so" do
      generated = property("{ type: integer, format: unix-time }")

      expect(generated.type("mod")).to include("const :it, ::Integer")
      expect(generated.warnings.join).to include('"integer:unix-time" has no Ruby type mapped')
    end

    it "refuses a type mapping for string:binary, which no codec can convert" do
      binary = OpenAPIKit::Codegen::RubyType.new(type: "::MyBlob", codec: "MyApp::BlobCodec")

      expect do
        generate_from(<<~YAML, type_mappings: { "string:binary" => binary })
          openapi: 3.0.3
          info: { title: T, version: "1.0" }
          paths: {}
        YAML
      end.to raise_error(OpenAPIKit::ConfigError, /does not convert a file with a codec/)
    end

    it "uses a configured type and codec" do
      money = OpenAPIKit::Codegen::RubyType.new(type: "::Money", codec: "MyApp::MoneyCodec")
      generated = generate_from(<<~YAML, type_mappings: { "string:money" => money })
        openapi: 3.0.3
        info: { title: T, version: "1.0" }
        paths: {}
        components:
          schemas:
            Mod: { type: object, required: [price], properties: { price: { type: string, format: money } } }
      YAML

      expect(generated.type("mod")).to include("const :price, ::Money", "MyApp::MoneyCodec.from_wire")
    end

    it "honours x-ruby-type on a single property" do
      generated = property('{ type: string, x-ruby-type: "::Token", x-ruby-codec: "MyApp::TokenCodec" }')

      expect(generated.type("mod")).to include("const :it, ::Token", "MyApp::TokenCodec.from_wire")
    end
  end

  # Rails matches in declaration order, so a templated segment declared first would
  # swallow a concrete sibling.
  it "declares concrete paths before the templated ones that would swallow them" do
    generated = document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                         "  /mods/{id}:", "    get:", "      operationId: getMod", "      tags: [mods]",
                         "      parameters:",
                         "        - { name: id, in: path, required: true, schema: { type: string } }",
                         %(      responses: { "204": { description: done } }),
                         "  /mods/featured:", "    get:", "      operationId: getFeatured",
                         "      tags: [mods]",
                         %(      responses: { "204": { description: done } }))

    routes = generated["api/routes.rb"].lines.grep(/mapper\./).map(&:strip)
    expect(routes.first).to include("/mods/featured")
    expect(routes.last).to include("/mods/:id")
  end

  # Without this a GET /mods/1.json truncates the id instead of 404ing.
  it "turns off Rails' format segment so a dotted path parameter stays intact" do
    generated = document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
                         "  /health:", "    get:", "      operationId: getHealth", "      tags: [system]",
                         %(      responses: { "204": { description: done } }))

    expect(generated["api/routes.rb"]).to include("format: false")
  end

  it "emits no routes, controllers or registry for a components-only document" do
    generated = schemas("Mod: { type: object, properties: { id: { type: integer } } }")

    expect(generated.paths).to eq(["api/types/mod.rb"])
  end

  describe "shapes Rails hands over differently" do
    def body(schema)
      document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
               "  /things:", "    post:", "      operationId: postThing", "      tags: [things]",
               "      requestBody:", "        required: true", "        content:",
               "          application/json: { schema: #{schema} }",
               %(      responses: { "204": { description: done } }))
    end

    # Rails' JSON parameter parser wraps a body that is not an object as { _json: parsed },
    # so decoding request_parameters directly fails on every valid request.
    it "reads a top-level array body from the key Rails wraps it under" do
      generated = body("{ type: array, items: { type: string } }")

      expect(generated["api/controllers/things_controller.rb"]).to include(%(request.request_parameters["_json"]))
    end

    it "reads an object body from request_parameters itself" do
      generated = body("{ type: object, properties: { a: { type: string } } }")

      source = generated["api/controllers/things_controller.rb"]
      expect(source).to include("from_wire(request.request_parameters)")
      expect(source).not_to include("_json")
    end
  end

  describe "security schemes" do
    def secured(scheme, requirement: "customAuth: []", principal: "::SpecPrincipal")
      yaml = [
        "openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:",
        "  /a:", "    get:", "      operationId: getA", "      tags: [t]",
        "      security: [{ #{requirement} }]",
        %(      responses: { "204": { description: done } }),
        "components:", "  securitySchemes:", *indent(scheme, 4)
      ].join("\n")

      generate_from(yaml, principal: principal)
    end

    # OpenAPI 3.0 fixes the four scheme types, but `http` takes any scheme name, so a
    # bespoke scheme reaches the controller as the name the document gave it.
    it "carries a custom http scheme name through" do
      generated = secured("customAuth: { type: http, scheme: HMAC-SHA256 }")

      expect(generated["api/security.rb"]).to include(%(scheme: "hmac-sha256"))
    end

    # x- is where anything the four types cannot express has to go, so it must survive.
    it "carries x- extensions on a scheme through" do
      generated = secured(<<~YAML)
        customAuth:
          type: http
          scheme: bearer
          x-signing-key: SIGNING_KEY
      YAML

      expect(generated["api/security.rb"]).to include(%(extensions: {"x-signing-key" => "SIGNING_KEY"}))
    end

    it "gives each scheme an authenticator returning the configured principal" do
      generated = secured("customAuth: { type: http, scheme: bearer }")

      expect(generated["api/security.rb"])
        .to include("module CustomAuth", "abstract!", "returns(T.nilable(::SpecPrincipal))")
    end

    # Where a credential lives is what the document declares, so an authenticator is
    # given it rather than knowing the header name and the scheme prefix itself.
    it "implements credential extraction from the declaration" do
      generated = secured("customAuth: { type: apiKey, in: cookie, name: session }")

      expect(generated["api/security.rb"])
        .to include("def scheme = CUSTOM_AUTH",
                    "def credential(request) = ::OpenAPIKit::Security.credential(scheme, request)")
    end

    it "decodes a basic scheme's credentials, since base64 is no use undecoded" do
      generated = secured("customAuth: { type: http, scheme: basic }")

      expect(generated["api/security.rb"])
        .to include("def basic_credential(request) = ::OpenAPIKit::Security.basic(scheme, request)")
    end

    it "offers no basic decoding for a scheme that is not basic" do
      generated = secured("customAuth: { type: http, scheme: bearer }")

      expect(generated["api/security.rb"]).not_to include("basic_credential")
    end

    it "puts the principal on the request and resolves it in the controller" do
      generated = secured("customAuth: { type: http, scheme: bearer }")

      expect(generated["api/operations/get_a.rb"]).to include("const :principal, ::SpecPrincipal")
      expect(generated["api/controllers/t_controller.rb"])
        .to include("principal = authenticate_get_a",
                    "Api.registry.custom_auth.authenticate(request: request, scopes: [])",
                    "raise(::OpenAPIKit::SecurityError)")
    end

    it "resolves every alternative through the registry, in document order" do
      generated = secured(
        "customAuth: { type: http, scheme: bearer }\nkeyAuth: { type: apiKey, in: header, name: X-Key }",
        requirement: "customAuth: [read] }, { keyAuth: []"
      )

      attempts = generated["api/controllers/t_controller.rb"].lines.grep(/-> \{/).map(&:strip)
      expect(attempts.first).to include("custom_auth", %(scopes: ["read"]))
      expect(attempts.last).to include("key_auth", "scopes: []")
    end

    # An anonymous alternative means the request may arrive without a principal.
    it "makes the principal nilable when the document offers anonymous access" do
      generated = secured("customAuth: { type: http, scheme: bearer }",
                          requirement: "customAuth: [] }, {")

      expect(generated["api/operations/get_a.rb"]).to include("const :principal, T.nilable(::SpecPrincipal)")
      expect(generated["api/controllers/t_controller.rb"]).not_to include("raise(::OpenAPIKit::SecurityError)")
    end

    it "refuses a document that declares security with no principal configured" do
      expect { secured("customAuth: { type: http, scheme: bearer }", principal: nil) }
        .to raise_error(OpenAPIKit::ConfigError, /no `principal` is configured/)
    end

    it "refuses two schemes required together, which it cannot yet type" do
      expect do
        secured("customAuth: { type: http, scheme: bearer }\nkeyAuth: { type: apiKey, in: header, name: X-Key }",
                requirement: "customAuth: [], keyAuth: []")
      end.to raise_error(OpenAPIKit::SchemaError, /requires customAuth and keyAuth together/)
    end

    # A server checks scope names; the flows' URLs tell a client where to get a token, so
    # openapi_kit does not carry them. Scopes are unioned, and a disagreement is not silent.
    it "unions scopes across OAuth flows and warns when one is described two ways" do
      generated = secured(<<~YAML, requirement: "oauth: [read]")
        oauth:
          type: oauth2
          flows:
            authorizationCode:
              authorizationUrl: https://example.com/authorize
              tokenUrl: https://example.com/token
              scopes: { read: "Read as a user" }
            clientCredentials:
              tokenUrl: https://example.com/machine-token
              scopes: { read: "Read as a machine", write: "Write" }
      YAML

      expect(generated["api/security.rb"]).to include(%(scopes: {"read" => "Read as a user", "write" => "Write"}))
      expect(generated.warnings.join).to include(%(The scope "read" of security scheme "oauth" is described two ways))
    end

    it "refuses a scheme type it does not know" do
      expect { secured("customAuth: { type: mutualTLS }") }
        .to raise_error(OpenAPIKit::SchemaError, /unsupported type "mutualTLS"/)
    end
  end

  describe "documents it refuses to generate" do
    def operation(body)
      document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:", *indent(body, 2))
    end

    it "requires an operationId" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, %r{GET /a has no operationId})
        /a:
          get:
            responses: { "204": { description: done } }
      YAML
    end

    it "requires an enum's values to be all one type" do
      expect { schemas("Mixed: { type: string, enum: [a, 1] }") }
        .to raise_error(OpenAPIKit::SchemaError, /Enum Mixed has values of type Integer, String/)
    end

    it "refuses two operationIds that normalise to the same name" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, /operationIds getMods, get_mods/)
        /a:
          get:
            operationId: getMods
            responses: { "204": { description: done } }
        /b:
          get:
            operationId: get_mods
            responses: { "204": { description: done } }
      YAML
    end

    it "refuses two tags that normalise to the same name" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, /tags Mods, mods/)
        /a:
          get:
            operationId: opA
            tags: [mods]
            responses: { "204": { description: done } }
        /b:
          get:
            operationId: opB
            tags: [Mods]
            responses: { "204": { description: done } }
      YAML
    end

    it "refuses a schema defined in terms of itself, naming the cycle" do
      cycle = /A is defined in terms of itself.*A -> B -> A/m

      expect { schemas(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, cycle)
        A: { type: array, items: { $ref: "#/components/schemas/B" } }
        B: { type: array, items: { $ref: "#/components/schemas/A" } }
      YAML
    end

    it "refuses a discriminated union member that has no name to map onto" do
      expect { schemas(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, /is an inline schema/)
        Pet:
          oneOf:
            - { type: object, required: [kind], properties: { kind: { type: string } } }
          discriminator: { propertyName: kind }
      YAML
    end

    it "refuses a path template Rails cannot route" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, /path template \{game-domain\}/)
        /g/{game-domain}:
          get:
            operationId: getGame
            responses: { "204": { description: done } }
      YAML
    end

    it "refuses a content type it can neither decode nor render" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, %r{content type text/plain})
        /a:
          post:
            operationId: postA
            requestBody:
              content: { text/plain: { schema: { type: string } } }
            responses: { "204": { description: done } }
      YAML
    end

    it "accepts a +json content type" do
      expect { operation(<<~YAML) }.not_to raise_error
        /a:
          post:
            operationId: postA
            requestBody:
              content:
                application/vnd.api+json:
                  schema: { type: object, properties: { a: { type: string } } }
            responses: { "204": { description: done } }
      YAML
    end

    it "refuses a parameter style it cannot decode" do
      undecodable = /style "deepObject", which openapi_kit does not decode/

      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, undecodable)
        /a:
          get:
            operationId: get_a
            parameters:
              - { name: q, in: query, style: deepObject, schema: { type: object } }
            responses: { "204": { description: done } }
      YAML
    end
  end
end
