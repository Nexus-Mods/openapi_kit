# oapi

Generates Sorbet-typed Rails server stubs from an OpenAPI 3 document. Handlers are strict
interfaces bound through your own container, responses are sealed, and authentication is
enforced where the document says it should be. Change the document and the build tells you
what no longer compiles.

```ruby
gem "oapi-runtime"          # what generated code calls

group :development do
  gem "oapi"                # the generator
end
```

## Contents

- [Generating](#generating)
- [Integrating with Rails](#integrating-with-rails)
- [Security](#security)
- [Custom types](#custom-types)
- [Files and binary responses](#files-and-binary-responses)
- [Not supported yet](#not-supported-yet)
- [Development](#development)

## Generating

```yaml
# oapi.yml
spec: openapi/mods.yaml
output: app/api
modules: [Mods, V1]
controller_base: Api::BaseController
container_prefix: v1
principal: "::Mods::Principal"
```

| Option | Meaning |
| --- | --- |
| `spec` | root OpenAPI document, resolved relative to this file |
| `output` | directory the tree is written to; oapi owns it |
| `modules` | namespace for every generated constant, so `Mods::V1::Types::Mod` |
| `controller_base` | class the generated controllers inherit from |
| `container_prefix` | prefixed onto every container key, so `v1.handlers.mods` |
| `principal` | the class a successful authentication produces |
| `type_mappings` | your Ruby type for a `type:format` pair |
| `name_overrides` | a different Ruby name for a schema |

The first four are required.

```console
$ bundle exec oapi generate -c oapi.yml
app/api/mods/v1/types/mod.rb
app/api/mods/v1/operations/list_mods.rb
app/api/mods/v1/handlers/mods.rb
app/api/mods/v1/security.rb
app/api/mods/v1/container.rb
app/api/mods/v1/routes.rb
app/api/mods/v1/mods_controller.rb
```

One constant per file at the path that constant implies, so Rails autoloads it. Each run
wipes `output`, but only after checking oapi generated every `.rb` in it.

## Integrating with Rails

**Autoload the output**, if it is not already under `app/`. An acronym in `modules`
becomes a directory, so it needs an inflection like any other acronym constant.

```ruby
# config/application.rb
config.autoload_paths << Rails.root.join("app/api").to_s
```

**Draw the routes.** They carry no prefix of their own, so mount them where you like.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  scope "/v1" do
    Mods::V1::Routes.draw(self)
  end
end
```

**Implement one handler per tag.** Miss an operation and Sorbet names the abstract method;
return an undeclared response variant and it will not compile.

```ruby
class ModsHandler
  extend T::Sig
  include Mods::V1::Handlers::Mods

  sig do
    override.params(request: Mods::V1::Operations::ListMods::Request)
            .returns(Mods::V1::Operations::ListMods::Response)
  end
  def list_mods(request:)
    mods = Mod.where(game: request.path.game_domain).page(request.query.page)

    Mods::V1::Operations::ListMods::Ok.new(body: mods.map { |mod| present(mod) })
  end
end
```

**Give the controllers a base class.** They inherit whatever you put there and need
nothing from it, so this is where your own concerns and error mapping live. A request
oapi cannot decode raises `Oapi::DecodeError`, carrying `detail` and a `json_pointer`
naming the field; oapi takes no view on the wire format.

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ApplicationController
    rescue_from Oapi::DecodeError, with: :unprocessable
    rescue_from Oapi::Unauthenticated, with: :unauthorized

    private

    def unauthorized = head(:unauthorized)

    def unprocessable(error)
      render json: { detail: error.detail, pointer: error.json_pointer },
             status: :unprocessable_content
    end
  end
end
```

**Assign the registry.** oapi generates a `Registry` struct with one slot per handler and
authenticator, and controllers read it from `Mods::V1.registry`. Rails instantiates
controllers itself, so they cannot be handed one. Omit a slot, or pass something that does
not implement its interface, and it does not compile.

```ruby
# config/initializers/oapi.rb
Rails.application.config.to_prepare do
  Mods::V1.registry = Mods::V1::Registry.new(
    mods: ModsHandler.new,
    system: SystemHandler.new,
    bearer_auth: BearerAuthenticator.new
  )
end
```

The registry is only oapi's boundary, not a dependency injection container. What each
handler needs behind it is yours, and a container is the right tool there. Unlike
controllers, *you* construct handlers, so constructor injection works:

```ruby
class ModsHandler
  include Mods::V1::Handlers::Mods            # oapi's interface
  include Deps["mod_repo", "search_client"]   # your container, via dry-auto_inject
end
```

Building the registry in `to_prepare` constructs every handler at boot, along with
whatever their constructors resolve, and reassigns them on a code reload.

## Security

Where the document declares `security`, the generated action authenticates before decoding
anything, and your handler receives the principal. Nothing else can reach the handler.

```yaml
security: [{ bearerAuth: [] }]              # the document's default
paths:
  /games/{gameDomain}/mods:
    post:
      security:                              # this operation overrides it
        - bearerAuth: [mods:write]
        - apiKeyAuth: []
```

Name what authentication produces, and seal it if your schemes produce different shapes:
that is what makes a handler's `case` exhaustive.

```ruby
module Mods::Principal
  extend T::Helpers
  sealed!

  class Token < T::Struct           # a JWT carries its permissions
    include Mods::Principal
    const :user_id, Integer
    const :permissions, T::Array[String]
  end

  class Key < T::Struct             # an API key does not
    include Mods::Principal
    const :client, String
  end
end
```

Then write one authenticator per scheme. Return `nil` to say this alternative was not
satisfied, so oapi tries the next one. Where the credential lives is what the document
declares, so `credential` is implemented for you.

```ruby
class BearerAuthenticator
  extend T::Sig
  include Mods::V1::Security::BearerAuth

  sig do
    override.params(request: ActionDispatch::Request, scopes: T::Array[String])
            .returns(T.nilable(Mods::Principal::Token))
  end
  def authenticate(request:, scopes:)
    token = credential(request) or return nil
    claims = Jwt.verify(token) or return nil
    return nil unless scopes.all? { |scope| claims.scopes.include?(scope) }

    Mods::Principal::Token.new(user_id: claims.sub, permissions: claims.scopes)
  end
end
```

`credential` reads the `Authorization` header and strips the declared scheme for `http`,
`oauth2` and `openIdConnect`, and reads the named header, query parameter or cookie for
`apiKey`. A `basic` scheme also gets `basic_credential`, returning the decoded
`[user, password]`.

Your handler then reads `request.principal`:

```ruby
def create_mod(request:)
  author = case request.principal
           when Mods::Principal::Token then "user-#{request.principal.user_id}"
           when Mods::Principal::Key then request.principal.client
           else T.absurd(request.principal)
           end
end
```

Alternatives are tried in document order and the first to produce a principal wins. If
none do, oapi raises `Oapi::Unauthenticated`. An operation offering anonymous
access (`security: [..., {}]`) makes the context `T.nilable` and raises nothing.

### What each scheme type gives you

`SCHEMES` is the document's `securitySchemes` as typed values, so an authenticator reads
its own configuration rather than restating the document.

| `type` | The scheme carries |
| --- | --- |
| `http` | `scheme`, `bearer_format` |
| `apiKey` | `location`, `parameter_name` |
| `oauth2` | the declared `scopes` catalogue |
| `openIdConnect` | `url`, the discovery document |

Plus any `x-` keys, on all four. OpenAPI 3.0 fixes these four types, so a bespoke scheme
is an `http` one with your own name, and anything the type cannot express goes in `x-`:

```yaml
securitySchemes:
  hmacAuth:
    type: http
    scheme: HMAC-SHA256
    x-signing-key: SIGNING_KEY
```

That reaches the scheme as `extensions`, which is also where an `oauth2` scheme's issuer
and JWKS URI belong, since OpenAPI has no field for them. An `openIdConnect` scheme needs
neither, because `url` discovers both.

## Custom types

A `type:format` pair with no built-in mapping is an error naming the config to add:

```yaml
type_mappings:
  "string:money":
    type: "::Money"
    codec: "MyApp::MoneyCodec"
```

`type` appears in signatures. `codec` converts it, and `Value` ties the halves together so
a codec cannot decode one type and encode another:

```ruby
module MyApp::MoneyCodec
  extend T::Sig
  extend T::Generic
  extend Oapi::Codec::Contract

  Value = type_template { { fixed: ::Money } }

  sig { override.params(value: Oapi::Wire).returns(::Money) }
  def self.from_wire(value) = ::Money.parse(Oapi::Codec::String.from_wire(value))

  sig { override.params(value: ::Money).returns(Oapi::Wire) }
  def self.to_wire(value) = value.format
end
```

`codec` need only name a constant answering `from_wire` and `to_wire`, so a codec that
needs configuration can `include` the contract instead and you name the instance you
built. The same override works inline, for one property rather than every occurrence of a
format:

```yaml
price:
  type: string
  x-ruby-type: "::Money"
  x-ruby-codec: "MyApp::MoneyCodec"
```

## Files and binary responses

A codec converts between a Ruby type and `Oapi::Wire`, the parsed value model every
supported media type shares: a multipart body's text fields go through the same codecs as
a JSON property, as do query and header values. A file is the one thing outside that
model, so it never goes through a codec. `format: binary` is handled in two places
instead, and refused everywhere else.

An upload is a property of a `multipart/form-data` request body. Such a body is still a
type, but it carries a `Form` where other types carry a `Codec`, because a file has no
wire form in either direction:

```ruby
class UploadModFileBody < T::Struct
  const :upload, ::ActionDispatch::Http::UploadedFile
  const :description, T.nilable(::String)

  module Form
    extend ::Oapi::Form::Contract

    sig { override.params(parts: ::Oapi::Form::Parts).returns(MyApi::Types::UploadModFileBody) }
    def self.from_parts(parts) = # ...
  end
end
```

`Oapi::Form::Parts` is what a multipart body arrives as —
`T::Hash[String, T.any(Oapi::Wire, ActionDispatch::Http::UploadedFile)]` — the one place a
file and a value share a container. The names follow the HTTP world rather than Rails':
the mapping is a *form* (`FormData` in browsers and Starlette, `multipart.Form` in Go,
`IFormCollection` in ASP.NET Core) and its members are *parts* (RFC 7578, and OpenAPI's own
wording that properties "are correlated with `multipart` parts"). `Oapi::Form::Contract`
is a one-way interface, so `Types::X::Form.is_a?(Oapi::Form::Contract)` answers whether a
type is form-decoded. The handler gets the struct:

```ruby
def upload_mod_file(request:)
  Blob.store!(io: request.body.upload.tempfile,
              filename: request.body.upload.original_filename)

  MyApi::Operations::UploadModFile::NoContent.new
end
```

A multipart schema must be an object, since a form is fields. A component may hold a file
and `$ref` works normally — it becomes a form type, decoded but never encoded, which the
binary rules make safe: nothing needing a wire form can reach it. A multipart body with no
file is an ordinary type on the ordinary codec path, the same as an urlencoded body of
that shape.

A binary response is the whole body, with whatever content type the document declares.
Its variant carries an `Oapi::Stream`, which is `T.any(::IO, ::StringIO)`, plus a `chunk`
size that defaults to 16KB:

```ruby
def download_mod_file(request:)
  MyApi::Operations::DownloadModFile::Ok.new(body: File.open(path, "rb"))
end
```

Every response variant answers `to_body`, returning a sealed `Oapi::Body` — `Empty`,
`Json` or `Binary` — and the generated controller cases over it to pick `head`, `render`
or a streamed body. Adding a kind of body would stop the controllers compiling until it
was handled. A streamed response sends no `Content-Length` and supports no `Range`.

`string:binary` has no entry in the default type mappings and cannot be given one, since
`type_mappings` names codecs and a file has nothing for one to convert. Convert to your
own type in the handler — `Shrine.upload(request.body.upload)` and the like. What does
work is `x-ruby-type` on a single property: that says the property is not a file but your
own type with your own codec, and it is then treated as an ordinary value everywhere.

## Not supported yet

Refused at generation time, rather than mis-generated:

- Parameter styles other than `simple` for path and `form` for query.
- One content type per request body, and it must be `application/json`, a `+json` type,
  `application/x-www-form-urlencoded` or `multipart/form-data`. A response body whose
  schema is `format: binary` may declare any content type at all.
- Two security schemes required together in one alternative (`{a: [], b: []}`). One scheme
  per alternative.
- A path template Rails cannot route, such as `{game-domain}`.

Documented behaviour to know about:

- Array and object query parameters follow Rails' conventions, not OpenAPI's: send
  `?tags[]=a&tags[]=b` and `?filter[lat]=1`, not `?tags=a&tags=b` or an exploded `?lat=1`.
- Schema keyword validation (`minLength`, `pattern`, `minimum`) is not enforced. Types and
  formats only.
- Codecs coerce strings, since path, query and header values arrive as strings. That
  leniency also applies to bodies, so `{"count": "42"}` satisfies `type: integer`.
- `format: binary` is only valid as a top-level property of a `multipart/form-data`
  request body, or as the whole schema of a response body. Anywhere else is refused: a
  file is bytes rather than a parsed value, so no codec can convert it. Use `format: byte`
  to carry bytes inside a value.
- An OAuth2 flow's `authorizationUrl`, `tokenUrl` and `refreshUrl` are not carried; they
  tell a client where to obtain a token and a resource server never calls them.

## Development

```console
$ bundle exec rake golden   # regenerate the output the specs compare against
$ bundle exec rake          # rspec, srb tc, rubocop
```

`srb tc` covers `spec/golden` as well as the generator, so output that does not typecheck
fails the build. `spec/dummy` is a Rails application whose `app/api` is generated the same
way, and `spec/generated/rails_request_spec.rb` issues real requests against it.

[ARCHITECTURE.md](ARCHITECTURE.md) covers the pipeline and where to change what.
