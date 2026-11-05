# Reusing swagger parameters

When building an API it can be common to have headers or parameters that are common to multiple actions.

## Scenario

For example, let's say we've got two endpoints:
- `GET /projects`
- `GET /books`

Both of these endpoints can be sorted using by `sort_by` and `sort_direction` parameters and both require a bearer token.

Here's what the swagger spec in our `ProjectsController` would look like:

```elixir
defmodule ProjectsController do
  use PhoenixSwagger

  swagger_path :index do
    get "/projects"
    produces "application/json"
    security([%{bearer: []}])
    parameters do      
      sort_by :query, :string, "The property to sort by"
      sort_direction :query, :string, "The sort direction", enum: [:asc, :desc], default: :asc
      company_id :string, :query, "The company id"
    end
  end
end
```

Our BooksController swagger would look very similar, also requiring the token and defining the `sort_by` and `sort_direction` parameters.

Why not an `Authorization` header parameter? OpenAPI 3.2 says header parameters named `Authorization`, `Accept` or `Content-Type` "SHALL be ignored", and the validator skips them. Describe the token with a security scheme instead, declared once in `swagger_info/0`:

```elixir
def swagger_info do
  %{
    info: %{version: "1.0", title: "My App"},
    components: %{securitySchemes: %{bearer: %{type: "http", scheme: "bearer"}}}
  }
end
```

## Extracting parameters into a module for reuse

The `swagger_path` macro layer is actually just some syntactic sugar over regular elixir functions, intended to be easily extended. Any function that accepts a `%PhoenixSwagger.Path.PathObject{}` as its first argument and returns an updated `%PathObject{}` can be used in the `swagger_path` macro.

Knowing this, we can easily extract some of the common logic into a module and reuse it in our controllers.

```elixir
defmodule CommonParameters do
  @moduledoc "Common parameter declarations for phoenix swagger"

  alias PhoenixSwagger.Path.PathObject
  import PhoenixSwagger.Path

  def authorization(path = %PathObject{}) do
    path |> security([%{bearer: []}])
  end

  def sorting(path = %PathObject{}) do
    path
    |> parameter(:sort_by, :query, :string, "The property to sort by")
    |> parameter(:sort_direction, :query, :string, "The sort direction", enum: [:asc, :desc], default: :asc)
  end
end
```

This can also be done using the `parameters` macro:

```elixir
def sorting(path = %PathObject{}) do
  parameters path do
    sort_by :query, :string, "The property to sort by"
    sort_direction :query, :string, "The sort direction", enum: [:asc, :desc], default: :asc
  end
end
```

## Reusing the common parameters

Now, instead of defining these parameters in every controller, we can just reference the `CommonParameters` module:

```elixir
defmodule ProjectsController do
  use PhoenixSwagger

  swagger_path :index do
    get "/users"
    produces "application/json"
    CommonParameters.authorization
    CommonParameters.sorting
    parameters do
      company_id :string, :query, "The company id"
    end
  end
end
```
