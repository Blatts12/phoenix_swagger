# Getting Started

`PhoenixSwagger` provides a mix compiler and mix task `phx.swagger.generate` that write an
OpenAPI 3.2 `json` document describing the API of your `phoenix` application.

You just need to add the swagger DSL to your controllers and then run this one mix task
to generate the JSON files.

## Installation

To use `PhoenixSwagger` with a phoenix application just add it to your list of
dependencies in the `mix.exs` file:

```elixir
def deps do
  [
    {:phoenix_swagger, "~> 0.9"},
    {:jsv, "~> 0.27"} # optional
  ]
end
```

`jsv` is an optional dependency of `phoenix_swagger`. You only need it for the validation plug and the test helper.

Append `:phoenix_swagger` to the list of compilers to automatically update the swagger files each time the app is compiled:

```elixir
def project do
[
  ...
  compilers: [:phoenix, :gettext] ++ Mix.compilers ++ [:phoenix_swagger],
  ...
end
```

The compiler skips generation when every swagger file is newer than your compiled modules and config files. Run `mix phx.swagger.generate` to regenerate them on demand. The check costs one file stat per compiled module, which is far cheaper than rebuilding the spec on every compile.

## Configuration

Add a config entry to your phoenix application specifying the output filename, router and endpoint modules used to generate the swagger file:

```elixir
config :my_app, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [
      router: MyAppWeb.Router,     # phoenix routes will be converted to swagger paths
      endpoint: MyAppWeb.Endpoint  # (optional) endpoint config used to build the servers list
    ]
  }
```

If multiple swagger files need to be generated, add additional entries to the project config:

```elixir
config :my_app, :phoenix_swagger,
  swagger_files: %{
    "booking-api.json" => [router: MyApp.BookingRouter],
    "reports-api.json" => [router: MyApp.ReportsRouter],
    "admin-api.json" => [router: MyApp.AdminRouter]
  }
```

Also you can configure JSON library to use:

```
config :phoenix_swagger, json_library: Jason
```
## Router

The outline of the swagger document should be returned from a `swagger_info/0` function
defined in your phoenix `Router.ex` module.

```elixir
defmodule MyApp.Router do
  use MyApp.Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MyApp do
    pipe_through :api
    resources "/users", UserController
  end

  def swagger_info do
    %{
      info: %{
        version: "1.0",
        title: "My App"
      }
    }
  end
end
```

The `version` and `title` are mandatory fields. By default the `version` will be `0.0.1`
and the `title` will be `<enter your title>` if you do not provide `swagger_info/0`
function.

See the [OpenAPI Object specification](https://spec.openapis.org/oas/v3.2.0.html#openapi-object) for the other fields you can include.
Set `servers` if your API routes do not live at the root location `/`. You can also describe your `tags` and add `components` such as `securitySchemes` here:

```elixir
%{
  servers: [%{url: "/api"}],
  info: %{..},
  tags: [%{name: "Users", description: "Operations about Users"}],
  components: %{securitySchemes: %{bearer: %{type: "http", scheme: "bearer"}}}
}
```

A word of caution when you upgrade from Swagger 2.0. Keys like `basePath`, `host`, `schemes` or `securityDefinitions` raise an `ArgumentError` that names their OpenAPI 3.2 replacement.

## Endpoint

The `servers` list is built from your phoenix `Endpoint` `url` config, unless `swagger_info/0` already sets `servers`.

```elixir
# config.exs
config :my_app, MyApp.Web.Endpoint,
  url: [host: "localhost"], # "servers": [{"url": "//localhost:4000"}] in the generated file
```

The URL has no scheme, so clients use the scheme the document was served with. A `scheme` in the `url` config, or an `https` config, adds the scheme to the URL.

If the `host` is configured to be set dynamically (either by `{:systems, "VAR"}` tuples or the `:load_from_system_env` flag), `servers` is omitted. SwaggerUI then sends requests to the same host that serves the document.

```elixir
# prod.exs
config :my_app, MyApp.Web.Endpoint,
  load_from_system_env: true, # Expects url host and port to be configured in Endpoint.init callback
  url: [host: "example.com", port: 80],
```

## Generate the OpenAPI file

Once you have a minimal configuration and `swagger_info` function in the router, run the `phx.swagger.generate`
mix task to write the JSON file:

```
mix phx.swagger.generate
```
