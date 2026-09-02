# How oapi works

```
spec files ─▶ Loader ─▶ Model ─▶ TypeRegistry ─▶ Emit::* ─▶ Writer
              parse     sealed    Ruby types      source     verify
                        structs   and codecs      text       and write
```

Two gems in one repo. `oapi-runtime` is what generated code calls: codecs, decoding
primitives, `Optional`, the errors. `oapi` is the generator and is never loaded in
production.

## The layers

**`Loader`** turns an OpenAPI document into the `Model`. It is the only place that
touches `openapi3_parser`, whose node types are declared in
`sorbet/rbi/shims/openapi3_parser.rbi`. It also hoists inline schemas into named types,
flattens `allOf`, and refuses documents oapi cannot generate from.

**`Model`** is sealed structs with no behaviour: `Schema`, `TypeDef`, `Operation`,
`Parameter`, `Status`. Adding a variant makes every `case` over it fail to typecheck
until handled, which is the point.

**`TypeRegistry`** answers "what Ruby type is this schema, and what converts it". It owns
`DEFAULT_TYPE_MAPPINGS` and merges your `type_mappings` over them.

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
| the security scheme catalogue | `Emit::Security` |
| what a document must contain | `Loader`, which raises `SchemaError` |
| a new built-in codec | `lib/oapi/codec/`, then the mappings table |

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
catches the things static checks cannot, like Rails handing back Symbol keys.
