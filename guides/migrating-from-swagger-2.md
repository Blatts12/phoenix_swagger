# Migrating from Swagger 2.0

Version 0.9 writes OpenAPI 3.2 documents instead of Swagger 2.0. Your controllers mostly keep working, because the DSL kept its names. What breaks sits around the DSL: the router's `swagger_info/0`, the validation dependency, and tests that match error text.

This guide assumes you run `phoenix_swagger` 0.8 and generate a `swagger.json` with `mix phx.swagger.generate`. We start with what the new output looks like, then walk through the upgrade.

## What changes in the generated file?

Your `swagger_path` blocks stay the same, but they render differently. Let's take this `show` action from a `UserController` as an example:

```elixir
swagger_path :show do
  get "/api/users/{id}"
  produces "application/json"
  parameter :id, :path, :integer, "User ID", example: 3
  response 200, "OK", Schema.ref(:User)
end
```

Version 0.8 rendered it like this. The other operation fields are trimmed for brevity:

```json
"produces": ["application/json"],
"parameters": [
  {"name": "id", "in": "path", "required": true, "description": "User ID",
   "type": "integer", "x-example": 3}
],
"responses": {
  "200": {"description": "OK", "schema": {"$ref": "#/definitions/User"}}
}
```

Version 0.9 renders the same block like this:

```json
"parameters": [
  {"name": "id", "in": "path", "required": true, "description": "User ID",
   "schema": {"type": "integer"}, "example": 3}
],
"responses": {
  "200": {
    "description": "OK",
    "content": {
      "application/json": {"schema": {"$ref": "#/components/schemas/User"}}
    }
  }
}
```

Let's break down the example above:

* `produces` no longer shows up in the output. It now picks the media types under `content`, and it defaults to `application/json`.
* The parameter type moved into `schema`, and `x-example` became a plain `example`.
* The reference points at `#/components/schemas/User`, because `definitions` became `components.schemas`.

A few more DSL calls change shape on the way out:

* `:body` parameters become the operation's `requestBody`. `:formData` parameters become a `multipart/form-data` body when one of them is a `:file`, and an `application/x-www-form-urlencoded` body otherwise.
* Array query parameters get `style: "form", explode: false`, so comma lists like `?tags=a,b` keep working.
* `collectionFormat` maps to `style` and `explode`. `tsv` has no OpenAPI 3 equivalent and raises.
* `nullable: true` adds `"null"` to the type instead of writing `x-nullable`.
* `discriminator :pet_type` renders as `{"propertyName": "pet_type"}`.

A word of caution about header parameters. OpenAPI 3.2 ignores header parameters named `Authorization`, `Accept` or `Content-Type`, and so does the validator. Move tokens to a security scheme, as [Reusing swagger parameters](reusing-swagger-parameters.md) shows.

One more change catches typos early. `parameter` and `response` raise a `KeyError` for an option they don't know, where 0.8 dropped it silently. `parameter` still passes options that start with `x-` through as specification extensions.

## How do I upgrade?

1. Swap the validation dependency in `mix.exs`. `jsv` replaces `ex_json_schema` and stays optional, so you only need it for the validation plug and the test helper.

   ```elixir
   def deps do
     [
       {:phoenix_swagger, "~> 0.9"},
       {:jsv, "~> 0.27"} # optional
     ]
   end
   ```

2. Run `mix deps.get`. Then run `mix deps.unlock ex_json_schema` if nothing else in your app uses it.

3. Move the Swagger 2.0 keys out of `swagger_info/0`. The next section shows each key and where it goes.

4. Regenerate the document with `mix phx.swagger.generate`. A leftover Swagger 2.0 key raises an `ArgumentError` that names its replacement, so run it until it passes.

5. Update tests that match validation messages word for word. [What changes in validation?](#what-changes-in-validation) lists what moved.

6. Update swagger-ui to 5.32.0 or later if you host your own copy. Older versions can't read OpenAPI 3.2. The bundled `PhoenixSwagger.Plug.SwaggerUI` already ships 5.34.1.

## Which keys moved?

The router's `swagger_info/0` is the one place where you wrote Swagger 2.0 by hand. Here is a typical 0.8 version with a host, a base path and two security definitions:

```elixir
def swagger_info do
  %{
    info: %{version: "1.0", title: "My App"},
    host: "api.example.com",
    basePath: "/api",
    schemes: ["https"],
    securityDefinitions: %{
      basic: %{type: "basic"},
      oauth: %{
        type: "oauth2",
        flow: "accessCode",
        authorizationUrl: "https://example.com/oauth/authorize",
        tokenUrl: "https://example.com/oauth/token",
        scopes: %{"read:users" => "Read users"}
      }
    }
  }
end
```

The same router in 0.9 describes the address with `servers` and the security definitions with `components.securitySchemes`:

```elixir
def swagger_info do
  %{
    info: %{version: "1.0", title: "My App"},
    servers: [%{url: "https://api.example.com/api"}],
    components: %{
      securitySchemes: %{
        basic: %{type: "http", scheme: "basic"},
        oauth: %{
          type: "oauth2",
          flows: %{
            authorizationCode: %{
              authorizationUrl: "https://example.com/oauth/authorize",
              tokenUrl: "https://example.com/oauth/token",
              scopes: %{"read:users" => "Read users"}
            }
          }
        }
      }
    }
  }
end
```

Let's break down the example above:

* `host`, `basePath` and `schemes` collapse into one `servers` URL. The validator reads its path, `/api`, as the base path of every operation.
* A `basic` definition becomes an `http` scheme with `scheme: "basic"`. `apiKey` definitions keep their shape.
* OAuth2 flows move under `flows`, keyed by flow name. `accessCode` is now `authorizationCode`, and `application` is now `clientCredentials`.
* `security` lists in your `swagger_path` blocks keep working, because they still name the scheme.

The rest of the Swagger 2.0 keys move like this:

* `consumes` and `produces` move into each `swagger_path`, where they pick the media types of the request body and responses.
* `definitions` moves to `swagger_definitions/0` in your controllers, or to `components.schemas`.
* `parameters` and `responses` move to `components.parameters` and `components.responses`.
* `swagger` goes away. The generator sets `openapi` for you.

If you leave out `servers`, the generator builds them from your endpoint `url` config, as it did with `host`. Without a `scheme` in that config the URL is scheme-relative, like `//localhost:4000`. Clients then use the scheme the document was served with.

## What changes in validation?

The validator now reads OpenAPI 3.1 and 3.2 files and checks them with `jsv`. You still load them the same way, at application start:

```elixir
PhoenixSwagger.Validator.parse_swagger_schema("priv/static/swagger.json")
```

Three things behave differently:

* Hand-written Swagger 2.0 files raise an `ArgumentError`. Regenerate them, or convert them to OpenAPI 3.1 or 3.2.
* Messages from JSON Schema checks use JSV wording. `Type mismatch. Expected Integer but got String.` is now `value is not of type integer`. Messages the validator writes itself, such as `Required property id was not present.`, stay the same.
* `format` is no longer checked. JSON Schema 2020-12 treats it as an annotation, so a malformed `email` passes.

`PhoenixSwagger.SchemaTest` keeps its API. `validate_resp_schema(conn, schema, "User")` now looks the name up in `#/components/schemas`. Its failure headline says "OpenAPI schema" instead of "swagger schema".

## When should I wait?

The upgrade buys you a document that current tools understand. You also get validation against the JSON Schema dialect that OpenAPI 3.1 and 3.2 actually use. The cost is a breaking release, rewritten error assertions, and the loss of `format` checks.

Tool support for OpenAPI 3.2 is still young. If your pipeline feeds the generated file to a client generator or a linter, check that it accepts `openapi: 3.2.0` first. If it doesn't yet, staying on 0.8 for a while is a fine choice.
