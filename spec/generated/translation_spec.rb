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
    dir = Pathname.new(Dir.mktmpdir)
    @generated_dirs << dir
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

  it "emits no routes, controllers or container for a components-only document" do
    generated = schemas("Mod: { type: object, properties: { id: { type: integer } } }")

    expect(generated.paths).to eq(["api/types/mod.rb"])
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
