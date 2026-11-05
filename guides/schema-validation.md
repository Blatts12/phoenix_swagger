# Schema Validation

Besides generating OpenAPI documents, `phoenix_swagger` validates the input parameters of your resources against them.
This guide assumes you added the optional `jsv` dependency, which checks values against JSON Schema 2020-12.

Suppose you have the following resource in your OpenAPI 3.2 document:

```
...
"/history": {
    "get": {
        "parameters": [
        {
            "name": "offset",
            "in": "query",
            "schema": {"type": "integer", "format": "int32"},
            "description": "Offset the list of returned results by this amount. Default is zero."
        },
        {
            "name": "limit",
            "in": "query",
            "schema": {"type": "integer", "format": "int32"},
            "description": "Integer of items to retrieve. Default is 5, maximum is 100."
        }]
     }
}
...
```

The `phoenix_swagger` provides `PhoenixSwagger.Validator.parse_swagger_schema/1` API to load a document by
the given path or list of paths. This API should be called during application startup. It builds the documents once
and stores the compiled index in `:persistent_term`. It accepts OpenAPI 3.1 and 3.2 documents and raises on Swagger 2.0 files.

After this, use one of the following to validate resources:
* the function `PhoenixSwagger.Validator.validate/2` using request path and parameters
* the default Plug `PhoenixSwagger.Plug.Validate`
* the function `PhoenixSwagger.ConnValidator.validate/1` using `conn`

### `Validator.validate/2`

For example:

```elixir
iex(1)> Validator.validate("/get/history", %{"limit" => "10"})
{:error, "value is not of type integer", "#/limit"}

iex(2)> Validator.validate("/get/history", %{"limit" => 10, "offset" => 100})
:ok
```


### Default Plug

To validate input parameters of your controllers with the default Plug, just add `PhoenixSwagger.Plug.Validate` to your router:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug PhoenixSwagger.Plug.Validate
end

scope "/api", MyApp do
  pipe_through :api
  post "/users", UsersController, :send
end
```

On validation errors, the default Plug returns `400` with the following body:
```json
{
  "error": {
    "path": "#/path/to/schema",
    "message": "value is not of type integer"
  }
}
```

The return code for validation errors is configurable via `:validation_failed_status` parameter.
If `conn.private[:phoenix_swagger][:valid]` is set to `true`, the Plug will skip validation.

### Which parameters get checked?

The plug reads each parameter from the place the document says it lives. Query, path, header, and form values arrive as strings, so the validator parses them into the declared type first. Then it checks the rest of the schema against the parsed value.

* A JSON `requestBody` (`application/json` or any `+json` type) is checked against its schema, either inline or a `$ref` to `components.schemas`.
* `application/x-www-form-urlencoded` and `multipart/form-data` bodies are checked field by field, like query parameters. A field without a `type`, such as a file part, accepts any value.
* `query`, `path`, and `header` parameters are checked for `required`, `type`, and `enum`. Parameters declared on the Path Item apply to every operation, and an operation parameter with the same name and location replaces them.
* Keywords such as `minimum`, `maximum`, `pattern`, and `maxLength` are checked after parsing.
* Arrays are split the way their `style` says. `form` with `explode: false` and `simple` split on commas, `spaceDelimited` on spaces, and `pipeDelimited` on pipes. A query array with the default `explode: true` reads every repeated key, as in `?ids=1&ids=2`.
* Header names match case-insensitively, because Plug lowercases them.

A word of caution about `Validator.validate/2`. It takes one map of already typed values, so it can't tell a form string from a JSON number. That's why it skips header parameters and only type-checks `string` and untyped form fields. Use `ConnValidator.validate/1` when you have a `conn`.

### What doesn't get checked?

The validator follows OpenAPI 3.2 where the spec leaves no choice, and skips a few things on purpose:

* `format` is an annotation in JSON Schema 2020-12, so `email` or `date-time` values are not rejected.
* Header parameters named `Accept`, `Content-Type`, or `Authorization` are ignored, as the spec requires. Use a security scheme for tokens.
* `cookie` and `querystring` parameters, parameters described with `content`, and `additionalOperations` are not validated.
* Each operation checks one request body media type. JSON wins over form types when both are declared.

### `ConnValidator.validate/1`

Use `ConnValidator.validate/1` to build your own Plugs. It accepts a `conn` and returns `{:ok, conn}` on validation success. Refer to source for error cases.
