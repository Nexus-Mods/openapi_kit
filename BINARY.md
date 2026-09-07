# Binary and file handling

How oapi handles `format: binary`, and why. `README.md` documents the behaviour; this is
the reasoning and a worked example.

The axis is values against streams, not JSON against everything else. `Oapi::Wire` is the
parsed value model every supported media type shares: `application/json` and `+json`,
form-urlencoded, and a multipart body's text fields all arrive as the same scalars, arrays
and hashes, as do path, query and header values. A codec converts between one of those and
a Ruby type.

A file is outside that model. It is opaque bytes that were never parsed, so no codec can
convert it, and a binary response sends bytes rather than a value. `Codec::Contract` stays
one thing, both directions, with `from_wire` narrowed from `T.untyped` to `Oapi::Wire`. A
codec that declares that parameter type then cannot decode a file: `Wire` is a closed
union, so `value.is_a?(UploadedFile)` is dead code and `srb tc` says so. Sorbet does allow
an override to widen a parameter back to `T.untyped`, which makes it writable again — so
this is the contract stating its intent, and the refusals below are what enforce it. Every other generator lands
in the same place, with files bypassing the serializer and a different type per direction:
`MultipartFile` and `StreamingResponseBody` in openapi-generator, `UploadFile` and
`StreamingResponse` in FastAPI, `IFormFile` and `FileResult` in NSwag.

There are two kinds of body:

- **values** — through codecs, whatever the media type
- **streams** — an uploaded file in, bytes out, never through a codec

A response says which it is by returning a sealed `Oapi::Body`, so the controller's `case`
is total and a new body kind fails to compile until it is handled. That `case` is one
private method per controller, taking the new `Oapi::Response` interface — status, body,
content type — which also lets each generated operation stop repeating those three
abstract signatures. Each operation's `Response` is still its own sealed module, so a
handler's return type and the exhaustiveness over its variants are unchanged.

`Body::Binary` holds an `Oapi::Stream`, which is `T.any(::IO, ::StringIO)` because
`StringIO` does not inherit from `IO`; a handler with a `String` in hand wraps it, and a
`Tempfile` answers `to_io`.

`chunk` is a prop with a default rather than a constant, and a binary response variant
exposes it, so a handler that knows its payload can choose. Disk-backed streams could
later skip chunking altogether — a `File` answers `to_path`, so `send_file` lets the web
server sendfile it — but that needs a path variant on `Body`, so it is out of scope here.

## Multipart request bodies

A multipart body is a named schema like any other body, so it stays a type: hoisted into
`Types::` when it is inline, or the component itself when it is a `$ref`. What it does not
have is a codec, because a property holding a file has no wire form in either direction.
It carries a `Form` instead, sibling to `Codec`, so a reader sees which boundary the type
crosses rather than noticing an absence:

- `Types::Mod::Codec.from_wire(value)` — a value, from any media type
- `Types::UploadFileBody::Form.from_parts(parts)` — a form, whose parts may hold files

`Codec` names a converter and its methods name the direction and the input, `from_wire`
and `to_wire`. `Form.from_parts` scans the same way, and the word after `from_` is the
whole distinction. Both words are borrowed rather than invented: six of the eight
ecosystems that name the parsed mapping at all call it a form, and RFC 7578 and the
OpenAPI 3 specification both call its members parts.

`Oapi::Form` names that input honestly — `T::Hash[String, T.any(Oapi::Wire,
UploadedFile)]` — rather than the `T.untyped` hash the framework hands over. It is the one
place a file and a value share a container, which is exactly what a multipart body is.

`Oapi::Form::Contract` is one-way, with only `from_parts`. Nobody hand-writes a form
decoder — `type_mappings` supplies codecs only — so it is not there to be implemented; it
is there to be programmed against, the way `Codec::Contract` can be. It gives an
application a type for "something that decodes a form", and a runtime answer to whether a
generated type is one.

The distinction is a variant in the model, not a predicate: the loader produces
`Model::FormDef` rather than `Model::ObjectDef` for an object schema with a file property,
so every `case` over `Model::TypeDef` fails to typecheck until it handles forms. That is
what makes it safe for `Emit::Types` to emit a `Form` where it would otherwise emit a
`Codec`, and it is why a form needs no `to_wire`: the binary-position refusals below mean
a `FormDef` is reachable only from a multipart request body.

One representational refusal remains — a multipart schema must be an object, since a form
is fields, and `type: string` under multipart would decode from a key Rails never
populates. `additionalProperties` needs none; a form decodes extras with `Decode.values`
exactly as an object does.

A multipart body without a file is an ordinary type on the ordinary codec path, since it
holds nothing a codec cannot convert. Only a file makes a form.

## Naming

`Wire` and `from_wire`/`to_wire` stay as they are. They were only ambiguous while files
were in the codec system; with those gone, a codec converts JSON and nothing else, and
`Body::Json` now names that kind of body explicitly rather than leaving `Wire` to carry
the distinction alone. Renaming to `from_json`/`to_json` would also collide with
ActiveSupport's `Object#to_json`, and would break every hand-written codec.

`Form` and `Parts` sit beside them on the same axis: `wire` is what parsing leaves
behind, a form's `parts` are what a multipart body leaves behind, and the difference
between them is exactly whether a file can be in one.

## Where binary is allowed

Two positions, and a `SchemaError` everywhere else:

- a top-level property of a `multipart/form-data` request body
- the whole schema of a response body

Nested in a JSON body, in a parameter, or below the top level of a multipart body it is
refused, because none of those can produce a file. `format: byte` remains the way to carry
bytes inside JSON. Those refusals are the enforcement: `to_wire_expr` raising on a binary
schema is only a backstop for an emitter bug.

Two consequences for the generator:

- `reject_undecodable_media_type!` must stop refusing arbitrary media types on a response
  whose schema is `format: binary`, or `application/octet-stream` never gets through.
- `string:binary` leaves `DEFAULT_TYPE_MAPPINGS`, since there is no codec to name.
  `ActionDispatch::Http::UploadedFile` and `Oapi::Decode.file` are hardcoded, as every
  other generator hardcodes its file type, and a `type_mappings` entry for
  `string:binary` is a `ConfigError` rather than a silently ignored one. A handler wanting
  Shrine or ActiveStorage converts in one line from the file it is given.

A worked example follows, in dependency order: the document, the runtime additions, what
oapi generates, and what an application writes.

---

`openapi/files.yaml`

```yaml
paths:
  /files/{id}:
    get:
      operationId: downloadFile
      tags: [files]
      parameters:
        - { name: id, in: path, required: true, schema: { type: string } }
      responses:
        "200":
          description: the file
          content:
            application/octet-stream:
              schema: { type: string, format: binary }
        "404":
          description: no such file
          content:
            application/problem+json:
              schema: { $ref: "#/components/schemas/ProblemDetails" }
  /files:
    post:
      operationId: uploadFile
      tags: [files]
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required: [upload]
              properties:
                upload: { type: string, format: binary }
                name: { type: string }
      responses:
        "204": { description: stored }
```

---

`oapi-runtime: lib/oapi/codec/contract.rb`

```ruby
module Oapi
  module Codec
    module Contract
      extend T::Sig
      extend T::Generic
      extend T::Helpers
      interface!

      Value = type_member

      sig { abstract.params(value: Oapi::Wire).returns(Value) }
      def from_wire(value); end

      sig { abstract.params(value: Value).returns(Oapi::Wire) }
      def to_wire(value); end
    end
  end
end
```

---

`oapi-runtime: lib/oapi/body.rb`

```ruby
module Oapi
  Stream = T.type_alias { T.any(::IO, ::StringIO) }

  DEFAULT_CHUNK = 16_384

  module Body
    extend T::Sig
    extend T::Helpers
    abstract!
    sealed!

    class Empty < T::Struct
      include Body
    end

    class Json < T::Struct
      include Body

      const :wire, Oapi::Wire
    end

    class Binary < T::Struct
      extend T::Sig
      include Body

      const :stream, Oapi::Stream
      const :chunk, ::Integer, default: Oapi::DEFAULT_CHUNK

      sig { params(block: T.proc.params(bytes: ::String).void).void }
      def each(&block)
        while (bytes = stream.read(chunk))
          block.call(bytes)
        end
      end
    end
  end
end
```

---

`oapi-runtime: lib/oapi/response.rb`

```ruby
module Oapi
  module Response
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(::Integer) }
    def status; end

    sig { abstract.returns(Oapi::Body) }
    def to_body; end

    sig { abstract.returns(T.nilable(::String)) }
    def content_type; end
  end
end
```

---

`oapi-runtime: lib/oapi/form.rb`

```ruby
module Oapi
  module Form
    Parts = T.type_alias do
      T::Hash[::String, T.any(Oapi::Wire, ::ActionDispatch::Http::UploadedFile)]
    end

    module Contract
      extend T::Sig
      extend T::Generic
      extend T::Helpers
      interface!

      Value = type_member

      sig { abstract.params(parts: Oapi::Form::Parts).returns(Value) }
      def from_parts(parts); end
    end
  end
end
```

---

`oapi-runtime: lib/oapi/decode.rb`

```ruby
module Oapi
  module Decode
    sig { params(value: T.untyped).returns(::ActionDispatch::Http::UploadedFile) }
    def self.file(value)
      return value if value.is_a?(::ActionDispatch::Http::UploadedFile)

      raise DecodeError.new("expected an uploaded file, got #{value.class}")
    end
  end
end
```

---

`generated: app/api/files/operations/download_file.rb`

```ruby
module Files
  module Operations
    module DownloadFile
      class Path < T::Struct
        extend T::Sig

        const :id, ::String
      end

      class Request < T::Struct
        extend T::Sig

        const :path, Path
        const :http_request, ::ActionDispatch::Request
      end

      module Response
        extend T::Helpers
        include ::Oapi::Response
        abstract!
        sealed!
      end

      class Ok < T::Struct
        extend T::Sig
        include Response

        const :body, ::Oapi::Stream
        const :chunk, ::Integer, default: ::Oapi::DEFAULT_CHUNK

        sig { override.returns(::Integer) }
        def status = 200

        sig { override.returns(::Oapi::Body) }
        def to_body = ::Oapi::Body::Binary.new(stream: body, chunk: chunk)

        sig { override.returns(T.nilable(::String)) }
        def content_type = "application/octet-stream"
      end

      class NotFound < T::Struct
        extend T::Sig
        include Response

        const :body, Files::Types::ProblemDetails

        sig { override.returns(::Integer) }
        def status = 404

        sig { override.returns(::Oapi::Body) }
        def to_body = ::Oapi::Body::Json.new(wire: Files::Types::ProblemDetails::Codec.to_wire(body))

        sig { override.returns(T.nilable(::String)) }
        def content_type = "application/problem+json"
      end
    end
  end
end
```

---

`generated: app/api/files/types/upload_file_body.rb`

```ruby
module Files
  module Types
    class UploadFileBody < T::Struct
      extend T::Sig

      const :upload, ::ActionDispatch::Http::UploadedFile
      const :name, T.nilable(::String)

      module Form
        extend T::Sig
        extend T::Generic
        extend ::Oapi::Form::Contract

        Value = type_template { { fixed: Files::Types::UploadFileBody } }

        sig { override.params(parts: ::Oapi::Form::Parts).returns(Files::Types::UploadFileBody) }
        def self.from_parts(parts)
          Files::Types::UploadFileBody.new(
            upload: ::Oapi::Decode.required(parts, "upload") { |v| ::Oapi::Decode.file(v) },
            name: ::Oapi::Decode.optional(parts, "name") { |v| ::Oapi::Codec::String.from_wire(v) },
          )
        end
      end
    end
  end
end
```

---

`generated: app/api/files/operations/upload_file.rb`

```ruby
module Files
  module Operations
    module UploadFile
      class Request < T::Struct
        extend T::Sig

        const :body, Files::Types::UploadFileBody
        const :http_request, ::ActionDispatch::Request
      end

      module Response
        extend T::Helpers
        include ::Oapi::Response
        abstract!
        sealed!
      end

      class NoContent < T::Struct
        extend T::Sig
        include Response

        sig { override.returns(::Integer) }
        def status = 204

        sig { override.returns(::Oapi::Body) }
        def to_body = ::Oapi::Body::Empty.new

        sig { override.returns(T.nilable(::String)) }
        def content_type = nil
      end
    end
  end
end
```

---

`generated: app/api/files/files_controller.rb`

```ruby
module Files
  class FilesController < ::Api::BaseController
    extend T::Sig

    sig { void }
    def download_file
      path_params = ::Oapi::Decode.gather(["id"]) { |name| request.path_parameters[name.to_sym] }

      decoded = Files::Operations::DownloadFile::Request.new(
        path: Files::Operations::DownloadFile::Path.new(
          id: ::Oapi::Decode.required(path_params, "id") { |v| ::Oapi::Codec::String.from_wire(v) },
        ),
        http_request: request
      )

      render_response(handler.download_file(request: decoded))
    end

    sig { void }
    def upload_file
      decoded = Files::Operations::UploadFile::Request.new(
        body: Files::Types::UploadFileBody::Form.from_parts(request.request_parameters),
        http_request: request
      )

      render_response(handler.upload_file(request: decoded))
    end

    private

    sig { params(result: ::Oapi::Response).void }
    def render_response(result)
      case (body = result.to_body)
      when ::Oapi::Body::Empty
        head(result.status)
      when ::Oapi::Body::Json
        render(json: body.wire, status: result.status, content_type: result.content_type)
      when ::Oapi::Body::Binary
        response.headers["Content-Type"] = result.content_type.to_s
        response.status = result.status
        self.response_body = body
      else T.absurd(body)
      end
    end

    sig { returns(Files::Handlers::Files) }
    def handler = Files.registry.files
  end
end
```

---

`application: app/api_handlers/files.rb`

```ruby
module ApiHandlers
  class Files
    extend T::Sig
    include Files::Handlers::Files

    sig { override.params(request: Files::Operations::DownloadFile::Request).returns(Files::Operations::DownloadFile::Response) }
    def download_file(request:)
      record = Upload.find_by(id: request.path.id)
      return Files::Operations::DownloadFile::NotFound.new(body: not_found) if record.nil?

      Files::Operations::DownloadFile::Ok.new(body: File.open(record.path, "rb"))
    end

    sig { override.params(request: Files::Operations::UploadFile::Request).returns(Files::Operations::UploadFile::Response) }
    def upload_file(request:)
      Upload.store!(io: request.body.upload.tempfile,
                    filename: request.body.upload.original_filename,
                    name: request.body.name)

      Files::Operations::UploadFile::NoContent.new
    end
  end
end
```
