# openapi_kit

Generates Sorbet-typed Rails server stubs from an OpenAPI 3 document. Handlers are strict
interfaces bound through a generated registry, responses are sealed, and authentication is
enforced where the document says it should be. Change the document and the build tells you
what no longer compiles.

```ruby
gem "openapi_kit"            # what generated code calls

group :development do
  gem "openapi_kit-codegen"  # the generator
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
# openapi_kit.yml
spec: openapi/petstore.yaml
output: app/api
modules: [Petstore, V1]
controller_base: Api::BaseController
principal: "::Petstore::Principal"
```

| Option | Meaning |
| --- | --- |
| `spec` | root OpenAPI document, resolved relative to this file |
| `output` | directory the tree is written to, which openapi_kit owns |
| `modules` | namespace for every generated constant, so `Petstore::V1::Types::Pet` |
| `controller_base` | class the generated controllers inherit from |
| `principal` | the class a successful authentication produces |
| `type_mappings` | your Ruby type for a `type:format` pair |
| `name_overrides` | a different Ruby name for a schema |

The first four are required.

```console
$ bundle exec openapi_kit generate -c openapi_kit.yml
app/api/petstore/v1/types/pet.rb
app/api/petstore/v1/operations/list_pets.rb
app/api/petstore/v1/handlers/pets.rb
app/api/petstore/v1/controllers/pets_controller.rb
app/api/petstore/v1/security.rb
app/api/petstore/v1/registry.rb
app/api/petstore/v1/routes.rb
```

One constant per file at the path that constant implies, so Rails autoloads it. Each run
wipes `output`, but only after checking openapi_kit generated every `.rb` in it.

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
    Petstore::V1::Routes.draw(self)
  end
end
```

**Implement one handler per tag.** Miss an operation and Sorbet names the abstract
method. Return an undeclared response variant and it will not compile.

```ruby
class PetsHandler
  extend T::Sig
  include Petstore::V1::Handlers::Pets

  sig do
    override.params(request: Petstore::V1::Operations::ListPets::Request)
            .returns(Petstore::V1::Operations::ListPets::Response)
  end
  def list_pets(request:)
    pets = Pet.where(store: request.path.store_id).page(request.query.page)

    Petstore::V1::Operations::ListPets::Ok.new(body: pets.map { |pet| present(pet) })
  end
end
```

**Give the controllers a base class.** They inherit whatever you put there and need
nothing from it, so this is where your own concerns and error mapping live. A request
openapi_kit cannot decode raises `OpenAPIKit::DecodeError`, carrying `detail` and a `json_pointer`
naming the field, and openapi_kit takes no view on the wire format.

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ApplicationController
    rescue_from OpenAPIKit::DecodeError, with: :unprocessable
    rescue_from OpenAPIKit::SecurityError, with: :unauthorized

    private

    def unauthorized = head(:unauthorized)

    def unprocessable(error)
      render json: { detail: error.detail, pointer: error.json_pointer },
             status: 422
    end
  end
end
```

**Assign the registry.** openapi_kit generates a `Registry` struct with one slot per handler and
authenticator, and controllers read it from `Petstore::V1.registry`. Rails instantiates
controllers itself, so they cannot be handed one. Omit a slot, or pass something that does
not implement its interface, and it does not compile.

```ruby
# config/initializers/openapi_kit.rb
Rails.application.config.to_prepare do
  Petstore::V1.registry = Petstore::V1::Registry.new(
    pets: PetsHandler.new(repo: PetRepo.new),
    system: SystemHandler.new,
    bearer_auth: BearerAuthenticator.new(decoder: TokenDecoder.new)
  )
end
```

The registry is openapi_kit's boundary and nothing more. What a handler needs behind it is
yours, and unlike controllers *you* construct handlers, so they take whatever they need.

Building the registry in `to_prepare` constructs every handler at boot, along with
whatever their constructors resolve, and reassigns them on a code reload.

## Security

Where the document declares `security`, the generated action authenticates before decoding
anything, and your handler receives the principal. Nothing else can reach the handler.

```yaml
security: [{ bearerAuth: [] }]              # the document's default
paths:
  /stores/{storeId}/pets:
    post:
      security:                             # this operation overrides it
        - bearerAuth: [pets:write]
        - apiKeyAuth: []
```

Name what authentication produces, and seal it if your schemes produce different shapes:
that is what makes a handler's `case` exhaustive.

```ruby
module Petstore::Principal
  extend T::Helpers
  sealed!

  class Token < T::Struct           # a JWT carries its permissions
    include Petstore::Principal
    const :user_id, Integer
    const :permissions, T::Array[String]
  end

  class Key < T::Struct             # an API key does not
    include Petstore::Principal
    const :client, String
  end
end
```

Then write one authenticator per scheme. Return `nil` to say this alternative was not
satisfied, so openapi_kit tries the next one. Where the credential lives is what the document
declares, so `credential` is implemented for you.

```ruby
class BearerAuthenticator
  extend T::Sig
  include Petstore::V1::Security::BearerAuth

  sig { params(decoder: TokenDecoder).void }
  def initialize(decoder:)
    @decoder = decoder
  end

  sig do
    override.params(request: ActionDispatch::Request, scopes: T::Array[String])
            .returns(T.nilable(Petstore::Principal::Token))
  end
  def authenticate(request:, scopes:)
    token = credential(request) or return nil
    claims = @decoder.decode(token) or return nil
    return nil unless scopes.all? { |scope| claims.scopes.include?(scope) }

    Petstore::Principal::Token.new(user_id: claims.sub, permissions: claims.scopes)
  end
end
```

`credential` reads the `Authorization` header and strips the declared scheme for `http`,
`oauth2` and `openIdConnect`, and reads the named header, query parameter or cookie for
`apiKey`. A `basic` scheme also gets `basic_credential`, returning the decoded
`[user, password]`.

Your handler then reads `request.principal`:

```ruby
def create_pet(request:)
  owner = case request.principal
           when Petstore::Principal::Token then "user-#{request.principal.user_id}"
           when Petstore::Principal::Key then request.principal.client
           else T.absurd(request.principal)
           end
end
```

Alternatives are tried in document order and the first to produce a principal wins. If
none do, openapi_kit raises `OpenAPIKit::SecurityError`. An operation offering anonymous
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
  extend OpenAPIKit::Codec::Contract

  Value = type_template { { fixed: ::Money } }

  sig { override.params(value: OpenAPIKit::Wire).returns(::Money) }
  def self.from_wire(value) = ::Money.parse(OpenAPIKit::Codec::String.from_wire(value))

  sig { override.params(value: ::Money).returns(OpenAPIKit::Wire) }
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

A file is the one thing outside `OpenAPIKit::Wire`, the value model every media type shares,
so it never goes through a codec. `format: binary` is handled in two places instead, and
refused everywhere else.

**An upload is a property of a `multipart/form-data` request body**, decoded through a
`Form` where other types carry a `Codec`:

```ruby
class UploadPetPhotoBody < T::Struct
  const :photo, ::ActionDispatch::Http::UploadedFile
  const :description, T.nilable(::String)
end

def upload_pet_photo(request:)
  Blob.store!(io: request.body.photo.tempfile)

  Petstore::V1::Operations::UploadPetPhoto::NoContent.new
end
```

**A binary response is the whole body**, taking a file on disk or a block that writes bytes:

```ruby
body: OpenAPIKit::Body::File.new(path: Rails.root.join("photos", name))

body: OpenAPIKit::Body::Stream.new(
  body: ->(sink) { Archive.open(pet) { |zip| IO.copy_stream(zip, sink) } }
)

body: OpenAPIKit::Body::Stream.new(body: ->(sink) { sink << header << row })
```

A path names the file and nothing more, so the server sends it however it likes: `sendfile`
under Puma, an `X-Accel-Redirect` or `X-Sendfile` under nginx and Apache through
`Rack::Sendfile`, and `Content-Length` comes off the file. A stream sends no
`Content-Length`, and whatever its block opens it also closes. Neither supports `Range`.

Every response variant answers `to_body`, a sealed `OpenAPIKit::Body` of `Empty`, `Json`,
`Stream` or `File`. `string:binary` takes no [`type_mappings`](#custom-types) entry, since a
file has nothing for a codec to convert.

## Not supported yet

Refused at generation time, rather than mis-generated:

- Parameter styles other than `simple` for path and `form` for query.
- One content type per request body, and it must be `application/json`, a `+json` type,
  `application/x-www-form-urlencoded` or `multipart/form-data`. A response body whose
  schema is `format: binary` may declare any content type at all.
- Two security schemes required together in one alternative (`{a: [], b: []}`). One scheme
  per alternative.
- A path template Rails cannot route, such as `{pet-id}`.

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
- An OAuth2 flow's `authorizationUrl`, `tokenUrl` and `refreshUrl` are not carried, since
  they tell a client where to obtain a token and a resource server never calls them.

## Development

```console
$ bundle exec rake golden   # regenerate the output the specs compare against
$ bundle exec rake          # rspec, srb tc, rubocop
```

`srb tc` covers `spec/golden` as well as the generator, so output that does not typecheck
fails the build. `spec/dummy` is a Rails application whose `app/api` is generated the same
way, and `spec/generated/rails_request_spec.rb` issues real requests against it.

[ARCHITECTURE.md](ARCHITECTURE.md) covers the pipeline and where to change what.
