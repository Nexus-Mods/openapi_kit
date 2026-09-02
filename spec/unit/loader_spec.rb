# frozen_string_literal: true

RSpec.describe Oapi::Loader do
  describe "schemas the old generator silently mistyped" do
    it "hoists an inline object property into a named type instead of String" do
      doc = load_spec(openapi(components: <<~YAML))
        Mod:
          type: object
          properties:
            meta:
              type: object
              properties: { note: { type: string } }
      YAML

      expect(property(type_named(doc, "Mod"), "meta").schema).to be_ir(Oapi::Ir::Ref.new(name: "ModMeta"))
      expect(type_named(doc, "ModMeta")).to be_a(Oapi::Ir::ObjectDef)
    end

    it "hoists an inline enum into a T::Enum instead of discarding the values" do
      doc = load_spec(openapi(components: <<~YAML))
        Mod:
          type: object
          properties:
            status: { type: string, enum: [live, hidden] }
      YAML

      enum = type_named(doc, "ModStatus")
      expect(enum).to be_a(Oapi::Ir::EnumDef)
      expect(enum.members.map(&:constant)).to eq(%w[Live Hidden])
      expect(enum.members.map(&:value)).to eq(%w[live hidden])
    end

    it "keeps the format of array items" do
      doc = load_spec(openapi(components: <<~YAML))
        Mod:
          type: object
          properties:
            dates: { type: array, items: { type: string, format: date-time } }
      YAML

      items = property(type_named(doc, "Mod"), "dates").schema.items
      expect(items).to be_a(Oapi::Ir::StringSchema)
      expect(items.format).to eq("date-time")
    end

    it "keeps a query parameter's default" do
      doc = load_spec(openapi(paths: <<~YAML))

        /mods:
          get:
            operationId: list_mods
            parameters:
              - { name: page, in: query, schema: { type: integer, default: 1, minimum: 1 } }
            responses: { "204": { description: done } }
      YAML

      schema = Oapi::Ir::Parameters.info(doc.operations.first.parameters.first).schema
      expect(schema.meta.default).to be_ir(Oapi::Ir::Default.new(value: 1))
      expect(schema.minimum).to eq(1)
    end

    it "keeps cookie parameters" do
      doc = load_spec(openapi(paths: <<~YAML))

        /mods:
          get:
            operationId: list_mods
            parameters:
              - { name: session, in: cookie, schema: { type: string } }
            responses: { "204": { description: done } }
      YAML

      expect(doc.operations.first.parameters.first).to be_a(Oapi::Ir::CookieParameter)
    end

    it "names a default response Default rather than Jsondefault" do
      doc = load_spec(openapi(paths: <<~YAML))

        /mods:
          get:
            operationId: list_mods
            responses:
              "200": { description: ok }
              "4XX": { description: client error }
              default: { description: fallback }
      YAML

      constants = doc.operations.first.responses.map { |r| Oapi::Ir::Statuses.constant(r.status) }
      expect(constants).to eq(%w[Ok Status4xx Default])
    end
  end

  describe "composition" do
    it "flattens allOf and unions the required sets" do
      doc = load_spec(openapi(components: <<~YAML))
        Base:
          type: object
          required: [id]
          properties: { id: { type: integer } }
        Mod:
          allOf:
            - $ref: "#/components/schemas/Base"
            - type: object
              required: [name]
              properties: { name: { type: string } }
      YAML

      mod = type_named(doc, "Mod")
      expect(mod.properties.map(&:name)).to eq(%w[id name])
      expect(mod.properties.map(&:required)).to eq([true, true])
    end

    it "unwraps the nullable-allOf-ref idiom into a nullable ref" do
      doc = load_spec(openapi(components: <<~YAML))
        User: { type: object, properties: { name: { type: string } } }
        Mod:
          type: object
          properties:
            owner:
              nullable: true
              allOf: [{ $ref: "#/components/schemas/User" }]
      YAML

      owner = property(type_named(doc, "Mod"), "owner").schema
      expect(owner).to be_a(Oapi::Ir::Ref)
      expect(owner.name).to eq("User")
      expect(owner.meta.nullable).to be(true)
    end

    it "resolves a discriminator mapping to component names" do
      doc = load_spec(openapi(components: <<~YAML))
        Cat: { type: object, properties: { kind: { type: string } } }
        Dog: { type: object, properties: { kind: { type: string } } }
        Pet:
          oneOf:
            - $ref: "#/components/schemas/Cat"
            - $ref: "#/components/schemas/Dog"
          discriminator:
            propertyName: kind
            mapping: { cat: "#/components/schemas/Cat", dog: "#/components/schemas/Dog" }
      YAML

      expect(type_named(doc, "Pet").tag)
        .to be_ir(Oapi::Ir::Tagged.new(property_name: "kind", mapping: { "cat" => "Cat", "dog" => "Dog" }))
    end

    it "infers an implicit discriminator mapping from the ref names" do
      doc = load_spec(openapi(components: <<~YAML))
        Cat: { type: object, properties: { kind: { type: string } } }
        Dog: { type: object, properties: { kind: { type: string } } }
        Pet:
          oneOf: [{ $ref: "#/components/schemas/Cat" }, { $ref: "#/components/schemas/Dog" }]
          discriminator: { propertyName: kind }
      YAML

      expect(type_named(doc, "Pet").tag.mapping).to eq("Cat" => "Cat", "Dog" => "Dog")
    end

    it "treats a union without a discriminator as untagged" do
      doc = load_spec(openapi(components: <<~YAML))
        Loose: { anyOf: [{ type: string }, { type: integer }] }
      YAML

      expect(type_named(doc, "Loose").tag).to be_a(Oapi::Ir::Untagged)
    end

    it "terminates on a self-referential schema" do
      doc = load_spec(openapi(components: <<~YAML))
        Node:
          type: object
          properties:
            next: { $ref: "#/components/schemas/Node" }
            kids: { type: array, items: { $ref: "#/components/schemas/Node" } }
      YAML

      node = type_named(doc, "Node")
      expect(property(node, "next").schema).to be_ir(Oapi::Ir::Ref.new(name: "Node"))
      expect(property(node, "kids").schema.items).to be_ir(Oapi::Ir::Ref.new(name: "Node"))
    end

    it "follows refs into another file" do
      shared = <<~YAML
        openapi: 3.0.3
        info: { title: Shared, version: "1.0" }
        paths: {}
        components:
          schemas:
            ProblemDetails: { type: object, properties: { title: { type: string } } }
      YAML
      doc = load_spec(openapi(components: <<~YAML), files: { "shared/components.yaml" => shared })
        Mod:
          type: object
          properties:
            error: { $ref: "shared/components.yaml#/components/schemas/ProblemDetails" }
      YAML

      expect(property(type_named(doc, "Mod"), "error").schema).to be_ir(Oapi::Ir::Ref.new(name: "ProblemDetails"))
      expect(type_named(doc, "ProblemDetails")).to be_a(Oapi::Ir::ObjectDef)
    end
  end

  describe "parameters" do
    it "makes path parameters required by construction" do
      doc = load_spec(openapi(paths: <<~YAML))

        /mods/{id}:
          get:
            operationId: get_mod
            parameters:
              - { name: id, in: path, required: true, schema: { type: integer } }
            responses: { "204": { description: done } }
      YAML

      parameter = doc.operations.first.parameters.first
      expect(parameter).to be_a(Oapi::Ir::PathParameter)
      expect(Oapi::Ir::Parameters.required?(parameter)).to be(true)
      expect(Oapi::Ir::PathParameter.props.keys).not_to include(:required)
    end

    it "rejects a path parameter that is not required" do
      yaml = openapi(paths: <<~YAML)

        /mods/{id}:
          get:
            operationId: get_mod
            parameters:
              - { name: id, in: path, required: false, schema: { type: integer } }
            responses: { "204": { description: done } }
      YAML

      expect { load_spec(yaml) }
        .to raise_error(Oapi::SchemaError, /Must be included and true for a path parameter/)
    end

    it "merges path-item parameters with operation parameters" do
      doc = load_spec(openapi(paths: <<~YAML))

        /mods/{id}:
          parameters:
            - { name: id, in: path, required: true, schema: { type: integer } }
          get:
            operationId: get_mod
            parameters:
              - { name: expand, in: query, schema: { type: boolean } }
            responses: { "204": { description: done } }
      YAML

      expect(doc.operations.first.parameters.map { |p| Oapi::Ir::Parameters.info(p).name })
        .to contain_exactly("id", "expand")
    end
  end

  describe "security" do
    it "models each scheme type as its own shape" do
      doc = load_spec(<<~YAML)
        openapi: 3.0.3
        info: { title: Test, version: "1.0" }
        paths: {}
        components:
          securitySchemes:
            apiKeyAuth: { type: apiKey, in: header, name: apikey }
            bearerAuth: { type: http, scheme: bearer, bearerFormat: JWT }
      YAML

      expect(doc.security_schemes).to contain_ir(
        Oapi::Ir::ApiKeyScheme.new(name: "apiKeyAuth", location: Oapi::Ir::ApiKeyLocation::Header,
                                   parameter_name: "apikey"),
        Oapi::Ir::HttpScheme.new(name: "bearerAuth", scheme: "bearer", bearer_format: "JWT")
      )
    end

    it "distinguishes an absent security key from an explicit empty one" do
      doc = load_spec(openapi(paths: <<~YAML))

        /a:
          get: { operationId: a, responses: { "204": { description: done } } }
        /b:
          get: { operationId: b, security: [], responses: { "204": { description: done } } }
      YAML

      by_id = doc.operations.to_h { |o| [o.id, o.security] }
      expect(by_id["a"]).to be_nil
      expect(by_id["b"]).to eq([])
    end

    it "reads OR alternatives and AND combinations" do
      doc = load_spec(openapi(paths: <<~YAML))

        /a:
          get:
            operationId: a
            security:
              - { bearerAuth: [read:user] }
              - { apiKeyAuth: [], mfa: [] }
              - {}
            responses: { "204": { description: done } }
      YAML

      security = doc.operations.first.security
      expect(security.map(&:schemes)).to eq([
                                              { "bearerAuth" => ["read:user"] },
                                              { "apiKeyAuth" => [], "mfa" => [] },
                                              {}
                                            ])
      expect(security.map(&:anonymous?)).to eq([false, false, true])
    end
  end

  describe "schemas it refuses to guess at" do
    it "names the fix when an operation has no operationId" do
      expect do
        load_spec(openapi(paths: "\n    /mods:\n      get:\n        responses: { \"204\": { description: done } }\n"))
      end
        .to raise_error(Oapi::SchemaError, %r{GET /mods has no operationId.*names the handler method}m)
    end

    it "refuses an enum that mixes value types" do
      expect { load_spec(openapi(components: "Mixed: { type: string, enum: [a, 1] }")) }
        .to raise_error(Oapi::SchemaError,
                        /Enum Mixed has values of type Integer, String.*all strings or all integers/m)
    end

    it "refuses a query-only style on a path parameter" do
      yaml = openapi(paths: <<~YAML)

        /mods/{id}:
          get:
            operationId: get_mod
            parameters:
              - { name: id, in: path, required: true, style: deepObject, schema: { type: object } }
            responses: { "204": { description: done } }
      YAML

      expect { load_spec(yaml) }
        .to raise_error(Oapi::SchemaError, /Path parameter "id" has style "deepObject".*simple, label or matrix/m)
    end
  end
end
