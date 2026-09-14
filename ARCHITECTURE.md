# How openapi_kit works

```
spec files ─▶ Loader ─▶ Model ─▶ TypeRegistry ─▶ Emit::* ─▶ Writer
              parse     sealed    Ruby types      source     verify
                        structs   and codecs      text       and write
```

Two gems in one repo. `openapi_kit` is what generated code calls: codecs, decoding
primitives, `Optional`, `Body`, `Response`, `Form`, the errors. `openapi_kit` is the generator
and is never loaded in production.

One distinction runs through all of it: **values against streams**. `OpenAPIKit::Wire` is the
parsed value model every supported media type shares — `application/json` and `+json`,
form-urlencoded, a multipart body's text fields, and path, query and header values all
arrive as the same scalars, arrays and hashes — and a codec converts between one of those
and a Ruby type, both ways. A file is outside that model, so it never reaches a codec:
`format: binary` decodes to an uploaded file and a binary response sends bytes. That is
why `Model::FormDef` exists rather than a predicate, and why a response answers a sealed
`OpenAPIKit::Body` rather than `OpenAPIKit::Wire`.

## The layers

**`Loader`** turns an OpenAPI document into the `Model`. It is the only place that
touches `openapi3_parser`, whose node types are declared in
`sorbet/rbi/shims/openapi3_parser.rbi`. It also hoists inline schemas into named types,
flattens `allOf`, and refuses documents openapi_kit cannot generate from.

**`Model`** is sealed structs: `Schema`, `TypeDef`, `Operation`, `Parameter`, `Status`.
Adding a variant makes every `case` over it fail to typecheck until handled, which is the
point — `FormDef` was added that way, and the compiler named every site that had to
change. Behaviour is limited to what a variant can answer about itself, like
`Schema.file?` and `Content#multipart?`; anything that needs the document or the config
belongs in the layers below.

**`TypeRegistry`** answers "what Ruby type is this schema, and what converts it". It owns
`DEFAULT_TYPE_MAPPINGS`, merges your `type_mappings` over them, and refuses one you may
not set: `string:binary`, since a file has no codec. It declines the question for a binary
schema rather than guessing, because the answer differs by direction — an uploaded file in,
a file or a block writing bytes out — and the emitter asking is the only thing that
knows which.

**`Emit::*`** each render one kind of file, through the `Buffer` DSL rather than
templates. `Source.file` wraps a body in its module nesting.

**`Writer`** verifies every rendered file parses with Prism, refuses duplicate paths,
then wipes and writes. Nothing is deleted until everything is known good.

## Where to change what

| To change | Edit |
| --- | --- |
| which Ruby type a `format` maps to | `TypeRegistry::DEFAULT_TYPE_MAPPINGS` |
| the shape of a generated struct or codec | `Emit::Types`, `Emit::Codecs` |
| request decoding, responses, handler interfaces | `Emit::Operations`, `Emit::Handlers` |
| routes or controllers | `Emit::Routes`, `Emit::Controllers` |
| the security scheme catalogue and authenticator interfaces | `Emit::Security` |
| how an application supplies handlers and authenticators | `Emit::Registry` |
| what a document must contain | `Loader`, which raises `SchemaError` |
| a new built-in codec | `lib/openapi_kit/codec/`, then the mappings table |
| how a request field is read out of a hash | `OpenAPIKit::Decode`, one method per required/nullable case |
| where `format: binary` may appear | `Loader#reject_misplaced_binary!` |
| how an uploaded file is decoded | `Model::FormDef`, then `Emit::Forms` |
| how a response body reaches Rack | `OpenAPIKit::Body`, then `Emit::Controllers` |

## Working on it

```console
$ bundle exec rake golden   # regenerate the trees the specs compare against
$ bundle exec rake          # rspec, srb tc, rubocop
```

Change an emitter and `rake` fails with a diff of the generated source. That diff is the
review: run `rake golden` and read it before committing. `srb tc` covers `spec/golden`
too, so output that does not typecheck fails the build.

`spec/dummy` is a real Rails application whose `app/api` is generated the same way.
`spec/generated/rails_request_spec.rb` issues real requests against it, which is what
catches the things static checks cannot: Rails handing back Symbol keys, a streamed
response actually reaching the client, a multipart upload arriving as the file
Rails parsed, and an under-scoped caller getting 403 rather than 401.

`spec/typecheck` holds the other half of that. `valid/` must typecheck; every file in
`invalid/` must fail, with `spec/generated/static_guarantees_spec.rb` asserting on the
`srb tc` output, because "this cannot compile" is not a property rspec can express.
