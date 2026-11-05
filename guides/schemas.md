# Schemas

Schema definitions are placed in a `swagger_definitions/0` function within each controller module.
The generator merges these maps into `components.schemas` of the [OpenAPI document](https://spec.openapis.org/oas/v3.2.0.html#components-object), so `Schema.ref(:User)` points at `#/components/schemas/User`.
Schema names may only use letters, digits, `.`, `-` and `_`, as the spec requires.

The `swagger_schema/2` macro can be used to build a schema definition using the functions provided by the `PhoenixSwagger.Schema` module.

Example:

```elixir
def swagger_definitions do
  %{
    User: swagger_schema do
      title "User"
      description "A user of the application"
      properties do
        name :string, "Users name", required: true
        id :string, "Unique identifier", required: true
        address :string, "Home address"
        preferences (Schema.new do
          properties do
            subscribe_to_mailing_list :boolean, "mailing list subscription", default: true
            send_special_offers :boolean, "special offers list subscription", default: true
          end
        end)
      end
      example %{
        name: "Joe",
        id: "123",
        address: "742 Evergreen Terrace"
      }
    end,
    Users: swagger_schema do
      title "Users"
      description "A collection of Users"
      type :array
      items Schema.ref(:User)
    end
  }
end
```

Schemas render as JSON Schema 2020-12, the dialect OpenAPI 3.2 uses. A few DSL options change shape on the way out:

* `nullable: true` adds `"null"` to `type`. On a `$ref` or a composed schema it wraps the checks in `anyOf` with `{"type": "null"}`.
* `exclusive_maximum(true)` turns the `maximum` value into a numeric `exclusiveMaximum`. You can also pass the number directly.
* A list given to `items` becomes `prefixItems`.
* `discriminator(:pet_type)` becomes `{"propertyName": "pet_type"}`.

To combine schemas with `all_of/2`, `one_of/2` and `any_of/2`, see [Combining Schemas](schema-composition.md).