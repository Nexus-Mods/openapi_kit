# frozen_string_literal: true

# OpenAPI 3.1 and 3.2 documents, whose schemas are JSON Schema 2020-12. The same API in
# either dialect generates the same code.
RSpec.describe "translating an OpenAPI 3.1+ document" do
  def schemas(version, body)
    generate_from(<<~YAML)
      openapi: #{version}
      info: { title: T, version: "1.0" }
      paths: {}
      components:
        schemas:
      #{body.strip.lines.map { |line| "    #{line}" }.join}
    YAML
  end

  def operation(body, version: "3.2.0")
    generate_from(<<~YAML)
      openapi: #{version}
      info: { title: T, version: "1.0" }
      paths:
      #{body.strip.lines.map { |line| "  #{line}" }.join}
    YAML
  end

  describe "the golden documents, rewritten for 3.1+" do
    it "generates the kitchen sink exactly as its 3.0 form does" do
      dir = generate("kitchen_sink_31.yaml", modules: %w[KitchenSink])[:dir]

      expect(relative_paths(dir)).to eq(relative_paths(golden("kitchen_sink", %w[KitchenSink])))
      relative_paths(dir).each do |path|
        expect(dir.join(path).read).to eq(golden("kitchen_sink", %w[KitchenSink]).join(path).read), path
      end
    end

    it "generates the server exactly as its 3.0 form does" do
      dir = generate("server_32.yaml", modules: %w[Server], **Golden::FIXTURES.fetch("server"))[:dir]

      expect(relative_paths(dir)).to eq(relative_paths(golden("server", %w[Server])))
      relative_paths(dir).each do |path|
        expect(dir.join(path).read).to eq(golden("server", %w[Server]).join(path).read), path
      end
    end
  end

  describe "schemas written in 2020-12 generate what their 3.0 form does" do
    {
      "a $ref beside other keywords, like 3.0's allOf idiom" => [
        <<~V30, <<~V31
          Status: { type: string, enum: [live, hidden] }
          Mod:
            type: object
            properties:
              status: { description: current status, default: live, allOf: [{ $ref: "#/components/schemas/Status" }] }
        V30
          Status: { type: string, enum: [live, hidden] }
          Mod:
            type: object
            properties:
              status: { $ref: "#/components/schemas/Status", description: current status, default: live }
        V31
      ],
      "a nullable reference written with anyOf" => [
        <<~V30, <<~V31
          User: { type: object, properties: { name: { type: string } } }
          Mod: { type: object, properties: { owner: { nullable: true, allOf: [{ $ref: "#/components/schemas/User" }] } } }
        V30
          User: { type: object, properties: { name: { type: string } } }
          Mod: { type: object, properties: { owner: { anyOf: [{ $ref: "#/components/schemas/User" }, { type: "null" }] } } }
        V31
      ],
      "a nullable union of several members" => [
        <<~V30, <<~V31
          A: { type: object, properties: { a: { type: string } } }
          B: { type: object, properties: { b: { type: string } } }
          Either: { nullable: true, oneOf: [{ $ref: "#/components/schemas/A" }, { $ref: "#/components/schemas/B" }] }
        V30
          A: { type: object, properties: { a: { type: string } } }
          B: { type: object, properties: { b: { type: string } } }
          Either: { oneOf: [{ $ref: "#/components/schemas/A" }, { $ref: "#/components/schemas/B" }, { type: "null" }] }
        V31
      ],
      "a nullable enum, which lists null among its values" => [
        <<~V30, <<~V31
          Mod: { type: object, properties: { status: { type: string, nullable: true, enum: [live, hidden] } } }
        V30
          Mod: { type: object, properties: { status: { type: [string, "null"], enum: [live, hidden, null] } } }
        V31
      ],
      "a nullable array of nullable items" => [
        <<~V30, <<~V31
          Mod: { type: object, properties: { tags: { type: array, nullable: true, items: { type: string, nullable: true } } } }
        V30
          Mod: { type: object, properties: { tags: { type: [array, "null"], items: { type: [string, "null"] } } } }
        V31
      ]
    }.each do |description, (v30, v31)|
      it description do
        expect(schemas("3.1.1", v31).sources).to eq(schemas("3.0.3", v30).sources)
      end
    end
  end

  it "reads a numeric exclusive bound as the bound itself" do
    dir = scratch_dir
    dir.join("api.yaml").write(<<~YAML)
      openapi: 3.1.1
      info: { title: T, version: "1.0" }
      paths: {}
      components:
        schemas:
          Page: { type: integer, exclusiveMinimum: 0, maximum: 100 }
    YAML
    config = config_for(spec: dir.join("api.yaml"), output: dir.join("generated"), modules: %w[Api])
    target = OpenAPIKit::Codegen::Loader.new(config: config).parse.types.first.target

    expect([target.minimum, target.exclusive_minimum, target.maximum, target.exclusive_maximum])
      .to eq([0, true, 100, false])
  end

  describe "the query operation" do
    let(:generated) do
      operation(<<~YAML)
        /mods:
          post:
            operationId: create_mod
            tags: [mods]
            responses: { "204": { description: created } }
          query:
            operationId: query_mods
            tags: [mods]
            requestBody:
              required: true
              content:
                application/json:
                  schema: { type: object, required: [page], properties: { page: { type: integer } } }
            responses:
              "200":
                description: ok
                content: { application/json: { schema: { type: object, properties: { total: { type: integer } } } } }
      YAML
    end

    it "routes QUERY beside the path's other methods" do
      expect(generated["routes.rb"]).to include(
        %(mapper.post("/mods", to: "api/controllers/mods#create_mod", format: false)),
        %(mapper.match("/mods", to: "api/controllers/mods#query_mods", via: :query, format: false))
      )
    end

    it "decodes its body and types its responses like any other operation" do
      expect(generated.operation("query_mods")).to include("const :body, Api::Types::QueryModsBody")
      expect(generated["handlers/mods.rb"]).to include("def query_mods(request:)")
    end
  end

  describe "documents it refuses to read" do
    {
      "the 3.0 nullable keyword" => ["Mod: { type: string, nullable: true }", %r{/Mod/nullable is OpenAPI 3\.0}],
      "a boolean exclusive bound, as 3.0 writes it" => [
        "Page: { type: integer, minimum: 0, exclusiveMinimum: true }", /exclusiveMinimum is a boolean/
      ],
      "a type array of more than one type" => [
        "Id: { type: [string, integer] }", /type is \["string", "integer"\]\. openapi_kit types a schema as one type/
      ],
      "a reference into another file" => [
        %(Mod: { $ref: "shared.yaml#/components/schemas/Mod" }), /only local references/
      ],
      "a reference that resolves to itself" => [
        %(A: { $ref: "#/components/schemas/B" }\nB: { $ref: "#/components/schemas/A" }), /refers to itself/
      ],
      "a tuple" => ["Pair: { type: array, prefixItems: [{ type: string }] }", /prefixItems: a tuple/],
      "a value of the wrong shape" => [
        "Mod: { type: object, required: name, properties: { name: { type: string } } }",
        %r{/Mod/required must be an array}
      ]
    }.each do |description, (body, message)|
      it "refuses #{description}" do
        expect { schemas("3.1.1", body) }.to raise_error(OpenAPIKit::SchemaError, message)
      end
    end

    it "refuses methods outside the ones OpenAPI names" do
      expect { operation(<<~YAML) }.to raise_error(OpenAPIKit::SchemaError, /additionalOperations/)
        /mods:
          additionalOperations:
            LINK: { operationId: link_mod, responses: { "204": { description: linked } } }
      YAML
    end

    it "refuses a version it does not read" do
      expect { operation("/a: {}", version: "4.0.0") }
        .to raise_error(OpenAPIKit::SchemaError, /declares openapi: "4\.0\.0"/)
    end
  end
end
