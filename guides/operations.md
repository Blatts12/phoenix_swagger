# Operations

`PhoenixSwagger` provides the `swagger_path/2` macro that generates an OpenAPI operation
for a phoenix controller action.

Example:

```elixir
use PhoenixSwagger

swagger_path :index do
  get "/posts"
  description "List blog posts"
  response 200, "Success"
end

def index(conn, _params) do
  posts = Repo.all(Post)
  render(conn, "index.json", posts: posts)
end
```

The `swagger_path` macro takes two parameters:

* Name of controller action;
* `do` block that describes the controller action.

Within the do-end block, the DSL provided by the `PhoenixSwagger.Path` module can be used.

Example:

```elixir
swagger_path :index do
  get "/api/v1/{org_id}/users"
  summary "Query for users"
  description "Query for users. This operation supports with paging and filtering"
  produces "application/json"
  tag "Users"
  operation_id "list_users"
  paging
  parameters do
    org_id :path, :string, "Organization ID", required: true
    zipcode :query, :string, "Address Zip Code", required: true, example: "90210"
    include :query, :array, "Related resources to include in response",
              items: [type: :string, enum: [:organisation, :favourites, :purchases]],
              style: "form", explode: false
  end
  response 200, "OK", Schema.ref(:Users)
  response 400, "Client Error"
end
```

The DSL keeps its Swagger 2.0 names, and the generator writes the OpenAPI 3.2 shapes:

* `consumes` picks the media types of the `requestBody`, and `produces` picks the media types of each response `content`. Both default to `application/json`.
* `:body` parameters become the `requestBody`. `:formData` parameters become a `multipart/form-data` body when one of them is a `:file`, and an `application/x-www-form-urlencoded` body otherwise.
* Types and constraints move into the parameter `schema`. An array query parameter gets `style: "form", explode: false`, so the comma form you know keeps working.
* `collectionFormat` still works and maps to `style` and `explode`. `tsv` has no OpenAPI 3 equivalent and raises.

The `swagger_path` macro layer is just some syntactic sugar over regular elixir functions. Therefore it can easily be extended, for instance, if we want to reuse some common parameters.

For more details on this take a look at [Reusing Swagger Parameters](https://hexdocs.pm/phoenix_swagger/reusing-swagger-parameters.html).

Note the imported `PhoenixSwagger.Path.delete/2` function may clash with your own `delete/2` function in the controller.
Often you can just remove this function call, since the route will be inferred automatically. If you need to customize the route for swagger, then use a qualified function call to disambiguate:

```elixir
  swagger_path :delete do
    PhoenixSwagger.Path.delete "/api/users/{id}"
    summary "Delete User"
    description "Delete a user by ID"
    parameter :id, :path, :integer, "User ID", required: true, example: 3
    response 203, "No Content - Deleted Successfully"
  end
```