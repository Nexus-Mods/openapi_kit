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
    config = Oapi::Codegen::Config.from_hash(
      { "spec" => "api.yaml", "output" => "generated", "modules" => %w[Api],
        "controller_base" => "ApiBaseController" }, base: dir
    )
    Oapi::Codegen::Generator.new(config: config).generate
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
        .to include("const :status, Api::Types::Status, factory: -> { Api::Types::Status::CODEC.from_wire(\"live\") }")
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
        .to include("const :owner, ::Oapi::Optional[T.nilable(Api::Types::User)]")
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
                                                 "::Oapi::Decode.first_of")
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
      "{ type: string, format: binary }" => "::ActionDispatch::Http::UploadedFile",
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

    it "falls back to the base type for an unrecognised format, and says so" do
      generated = property("{ type: integer, format: unix-time }")

      expect(generated.type("mod")).to include("const :it, ::Integer")
      expect(generated.warnings.join).to include('"integer:unix-time" has no Ruby type mapped')
    end

    it "uses a configured type and codec" do
      money = { "type" => "::Money", "codec" => "MyApp::MoneyCodec" }
      generated = generate_from(<<~YAML, "type_mappings" => { "string:money" => money })
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

  it "emits no routes, controllers or container for a components-only document" do
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

      expect(generated["api/things_controller.rb"]).to include(%(request.request_parameters["_json"]))
    end

    it "reads an object body from request_parameters itself" do
      generated = body("{ type: object, properties: { a: { type: string } } }")

      source = generated["api/things_controller.rb"]
      expect(source).to include("from_wire(request.request_parameters)")
      expect(source).not_to include("_json")
    end
  end

  describe "documents it refuses to generate" do
    def operation(body)
      document("openapi: 3.0.3", %(info: { title: T, version: "1.0" }), "paths:", *indent(body, 2))
    end

    it "requires an operationId" do
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, %r{GET /a has no operationId})
        /a:
          get:
            responses: { "204": { description: done } }
      YAML
    end

    it "requires an enum's values to be all one type" do
      expect { schemas("Mixed: { type: string, enum: [a, 1] }") }
        .to raise_error(Oapi::SchemaError, /Enum Mixed has values of type Integer, String/)
    end

    it "refuses two operationIds that normalise to the same name" do
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, /operationIds getMods, get_mods/)
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
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, /tags Mods, mods/)
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
      expect { schemas(<<~YAML) }.to raise_error(Oapi::SchemaError, /A is defined in terms of itself.*A -> B -> A/m)
        A: { type: array, items: { $ref: "#/components/schemas/B" } }
        B: { type: array, items: { $ref: "#/components/schemas/A" } }
      YAML
    end

    it "refuses a discriminated union member that has no name to map onto" do
      expect { schemas(<<~YAML) }.to raise_error(Oapi::SchemaError, /is an inline schema/)
        Pet:
          oneOf:
            - { type: object, required: [kind], properties: { kind: { type: string } } }
          discriminator: { propertyName: kind }
      YAML
    end

    it "refuses a path template Rails cannot route" do
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, /path template \{game-domain\}/)
        /g/{game-domain}:
          get:
            operationId: getGame
            responses: { "204": { description: done } }
      YAML
    end

    it "refuses a content type it can neither decode nor render" do
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, %r{content type text/plain})
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
      expect { operation(<<~YAML) }.to raise_error(Oapi::SchemaError, /style "deepObject", which oapi does not decode/)
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
