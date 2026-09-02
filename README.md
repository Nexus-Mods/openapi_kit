# oapi

Generates Sorbet-typed Rails server stubs from an OpenAPI 3 document. Handlers are strict
interfaces bound through your own container. Responses are sealed, so Sorbet fails the
build if an endpoint forgets a status it declares.

```ruby
gem "oapi-runtime"          # what generated code calls

group :development do
  gem "oapi"                # the generator
end
```

## Generating

```yaml
# oapi.yml
spec: openapi/mods.yaml
output: app/api
modules: [Mods, V1]
controller_base: Api::BaseController
container_prefix: v1
```

| Option | Meaning |
| --- | --- |
| `spec` | root OpenAPI document, resolved relative to this file |
| `output` | directory the tree is written to; oapi owns it |
| `modules` | namespace for every generated constant, so `Mods::V1::Types::Mod` |
| `container_prefix` | prefixed onto every container key, so `v1.handlers.mods` |
| `controller_base` | class the generated controllers inherit from |
| `type_mappings` | your Ruby type for a `type:format` pair |
| `name_overrides` | a different Ruby name for a schema |

```console
$ bundle exec oapi generate -c oapi.yml
app/api/mods/v1/types/mod.rb
app/api/mods/v1/operations/list_mods.rb
app/api/mods/v1/handlers/mods.rb
app/api/mods/v1/mods_controller.rb
app/api/mods/v1/routes.rb
app/api/mods/v1/container.rb
```

One constant per file at the path that constant implies, so Rails autoloads it. Each run
wipes `output`, but only after checking oapi generated every `.rb` in it.

## Integrating with Rails

Autoload the output, if it is not already under `app/`:

```ruby
# config/application.rb
config.autoload_paths << Rails.root.join("app/api").to_s
```

An acronym in `modules` becomes a directory, so it needs an inflection:

```ruby
# config/initializers/inflections.rb
ActiveSupport::Inflector.inflections { |inflect| inflect.acronym "API" }
```

Draw the routes. They carry no prefix of their own, so mount them where you like:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  scope "/v1" do
    Mods::V1::Routes.draw(self)
  end
end
```

Implement one handler per tag. Miss an operation and Sorbet names the abstract method;
return an undeclared variant and it will not compile:

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

Give the controllers a base class. `oapi_container` is the only method they need from it:

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ApplicationController
    rescue_from Oapi::DecodeError, with: :unprocessable

    private

    def oapi_container = Rails.configuration.x.api_container

    def unprocessable(error)
      render json: { title: "Unprocessable Content", detail: error.detail, pointer: error.json_pointer },
             status: :unprocessable_content,
             content_type: "application/problem+json"
    end
  end
end
```

An undecodable request raises `Oapi::DecodeError`, carrying `detail` and a `json_pointer`
naming the field. oapi takes no view on the wire format; the example answers RFC 9457.

Build the container and verify it at boot, so a missing registration fails boot rather
than the first request that needs it. Use `to_prepare`, or a reload leaves handlers
holding stale constants:

```ruby
# config/initializers/oapi.rb
Rails.application.config.to_prepare do
  container = Dry::Container.new
  container.register("v1.handlers.mods") { ModsHandler.new }
  container.register("v1.handlers.system") { SystemHandler.new }

  Rails.configuration.x.api_container = container
  Mods::V1::Container.verify!(container)
end
```

## Custom types

A `type:format` pair with no built-in mapping is an error naming the config to add:

```yaml
type_mappings:
  "string:money":
    type: "::Money"
    codec: "MyApp::MoneyCodec"
```

`type` appears in signatures. `codec` converts it, and `Value` ties the halves together
so a codec cannot decode one type and encode another:

```ruby
module MyApp::MoneyCodec
  extend T::Sig
  extend T::Generic
  extend Oapi::Codec::Contract

  Value = type_template { { fixed: ::Money } }

  sig { override.params(value: Oapi::Wire::Out).returns(::Money) }
  def self.from_wire(value) = ::Money.parse(Oapi::Codec::String.from_wire(value))

  sig { override.params(value: ::Money).returns(Oapi::Wire::Out) }
  def self.to_wire(value) = value.format
end
```

`codec` only has to name a constant that answers `from_wire` and `to_wire`. A codec that
needs configuration can `include` the contract instead, and you name the instance you
built. The same override works inline, for one property rather than every occurrence of
a format:

```yaml
price:
  type: string
  x-ruby-type: "::Money"
  x-ruby-codec: "MyApp::MoneyCodec"
```

## Not supported yet

- Security schemes are read from the document but not enforced or surfaced to handlers.
- Parameter styles other than `simple` for path and `form` for query.
- Array and object query parameters follow Rails' conventions, not OpenAPI's: send
  `?tags[]=a&tags[]=b` and `?filter[lat]=1`, not `?tags=a&tags=b` or an exploded `?lat=1`.
- One content type per request body, and it must be `application/json`, a `+json` type,
  `application/x-www-form-urlencoded` or `multipart/form-data`.
- `format: binary` in a response. It maps to a multipart upload, which a response cannot
  produce. Use `format: byte`, or map `string:binary` yourself.
- Schema keyword validation (`minLength`, `pattern`, `minimum`). Types and formats only.
- Codecs coerce strings, since path, query and header values arrive as strings. That
  leniency also applies to bodies, so `{"count": "42"}` satisfies `type: integer`.

Everything above is refused at generation time rather than mis-generated, except the last
two, which are documented behaviour.

## Development

```console
$ bundle exec rake        # rspec, srb tc, rubocop
```

`srb tc` covers `spec/golden` as well as the generator, so output that does not typecheck
fails the build. `spec/dummy` is a Rails application whose `app/api` is generated before
the suite runs; `spec/generated/rails_request_spec.rb` issues real requests against it.
