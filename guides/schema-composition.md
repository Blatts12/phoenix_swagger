# Combining Schemas

Real payloads rarely have one fixed shape. A payment is either a card or a bank transfer, and a dog is a pet with a few extra fields. OpenAPI 3.2 describes these cases with `allOf`, `oneOf` and `anyOf`. `PhoenixSwagger.Schema` has one function for each.

This guide assumes you can define schemas with `swagger_schema` and point at them with `Schema.ref/1`, as the [Schemas](schemas.md) guide shows.

## Which keyword do I need?

Each keyword answers a different question about the value:

* `all_of/2`: the value matches every listed schema. Use it to extend a base schema.
* `one_of/2`: the value matches exactly one listed schema. Use it for alternatives that never overlap.
* `any_of/2`: the value matches at least one listed schema. Use it for alternatives that may overlap.
* `discriminator/2`: names the property that tells the alternatives apart. Tools use it as a hint, and it never changes the validation result.

## How do I extend a schema with all_of?

Inheritance is the classic case. A `Dog` is a `Pet` plus a pack size. In your controller's `swagger_definitions/0`, the dog lists the pet and its own extra properties:

```elixir
def swagger_definitions do
  %{
    Pet: swagger_schema do
      title "Pet"
      properties do
        name :string, "Pet name", required: true
        pet_type :string, "Kind of pet"
      end
      discriminator :pet_type
    end,
    Dog: swagger_schema do
      title "Dog"
      all_of [
        Schema.ref(:Pet),
        Schema.new do
          properties do
            pack_size :integer, "Size of the pack", minimum: 0
          end
        end
      ]
    end
  }
end
```

The generator writes `Dog` like this:

```json
"Dog": {
  "type": "object",
  "title": "Dog",
  "allOf": [
    {"$ref": "#/components/schemas/Pet"},
    {
      "type": "object",
      "properties": {
        "pack_size": {"type": "integer", "minimum": 0, "description": "Size of the pack"}
      }
    }
  ]
}
```

Let's break down the example above:

* A dog must pass both schemas. It needs a `name` and a `pet_type`, and any `pack_size` must be zero or more.
* `discriminator :pet_type` on `Pet` also marks `pet_type` as required.
* The discriminator tells documentation tools and client generators that `pet_type: "Dog"` means the `Dog` schema. The value matches the schema name, so you don't need an extra mapping.

A word of caution here. The spec says this parent form of the discriminator only helps outside validation. Validating a body against `Pet` never looks at `Dog`, so a `pack_size` of `-1` passes. If an endpoint accepts any kind of pet, list the kinds with `one_of/2` instead.

## How do I accept one of several shapes?

`one_of/2` fits payloads that come in distinct kinds. Here a payment is either a card or a bank account, and the `method` property says which. These entries go in the same `swagger_definitions/0` map:

```elixir
Payment: swagger_schema do
  title "Payment"
  one_of [Schema.ref(:Card), Schema.ref(:BankAccount)]
  discriminator :method
end,
Card: swagger_schema do
  properties do
    method :string, "Payment method", required: true, enum: [:Card]
    number :string, "Card number", required: true
  end
end,
BankAccount: swagger_schema do
  properties do
    method :string, "Payment method", required: true, enum: [:BankAccount]
    iban :string, "IBAN", required: true
  end
end
```

`Payment` renders like this:

```json
"Payment": {
  "type": "object",
  "title": "Payment",
  "oneOf": [
    {"$ref": "#/components/schemas/Card"},
    {"$ref": "#/components/schemas/BankAccount"}
  ],
  "discriminator": {"propertyName": "method"},
  "required": ["method"]
}
```

Let's break down the example above:

* Each alternative pins `method` with a one-value `enum`. That keeps the shapes apart, so no payment can match both.
* The `method` values match the schema names, `Card` and `BankAccount`. Without an explicit mapping, the spec maps a discriminator value to the component with the same name.
* Every alternative is listed in `oneOf` itself, as the spec requires. A discriminator never discovers schemas on its own.

You use `Payment` like any other schema. This operation takes one as its request body:

```elixir
swagger_path :pay do
  post "/api/orders/{id}/payments"
  parameter :id, :path, :integer, "Order ID"
  parameter :payment, :body, Schema.ref(:Payment), "Payment details", required: true
  response 201, "Paid"
end
```

The validator checks `oneOf` strictly. A body like `%{"method" => "Cash"}` fails with `value did not conform to one of the given schemas` at `#`.

A word of caution about overlapping alternatives. JSON Schema objects accept extra properties by default. If two alternatives only differ by their required fields, a payload carrying both sets of fields matches both. Then `oneOf` fails with `value did conform to more than one of the given schemas`. Pin a property with `enum` as above, or switch to `any_of/2` when overlap is fine.

## When is any_of the better fit?

`any_of/2` accepts a value that matches one alternative or several. Say a contact needs an email, a phone number, or both:

```elixir
Contact: swagger_schema do
  title "Contact"
  any_of [Schema.ref(:EmailContact), Schema.ref(:PhoneContact)]
end,
EmailContact: swagger_schema do
  properties do
    email :string, "Email address", required: true
  end
end,
PhoneContact: swagger_schema do
  properties do
    phone :string, "Phone number", required: true
  end
end
```

A contact with both fields passes, which `one_of/2` would reject. A contact with neither fails with `value did not conform to any of the given schemas`.

For a value that is one of two primitive types, a type list is shorter. Writing `id [:string, :integer], "Order ID"` inside a `properties` block renders `"type": ["string", "integer"]`.

A word of caution about non-object alternatives. `swagger_schema` always starts from `type: object`, so a `one_of` over strings and integers inside it can never match. Build that schema as a property with `Schema.one_of(%Schema{}, [...])`, or use a type list.

## How does nullable work with compositions?

`nullable: true` can't just add `"null"` to the type of a composed schema, because the alternatives would still reject `null`. The generator wraps the checks in an `anyOf` with a null branch instead. This property lets an unpaid order carry `null` as its payment:

```elixir
Order: swagger_schema do
  properties do
    payment Schema.ref(:Payment), "Payment, if the order is paid", nullable: true
  end
end
```

The `payment` property renders like this:

```json
"payment": {
  "description": "Payment, if the order is paid",
  "anyOf": [
    {"$ref": "#/components/schemas/Payment"},
    {"type": "null"}
  ]
}
```

The same wrapping applies to `nullable` on a schema built with `all_of/2`, `one_of/2` or `any_of/2`. `title`, `description`, `example` and `default` stay outside the wrapper. Everything else moves inside it, the discriminator included, so it stays next to its `oneOf`.

## What isn't covered yet?

The DSL has no helper for `not`, or for the discriminator's `mapping` and `defaultMapping`. You can still write those parts as plain maps in `swagger_definitions/0`, which the generator copies into the document unchanged:

```elixir
Payment: %{
  "type" => "object",
  "oneOf" => [
    %{"$ref" => "#/components/schemas/Card"},
    %{"$ref" => "#/components/schemas/BankAccount"}
  ],
  "discriminator" => %{
    "propertyName" => "method",
    "mapping" => %{
      "card" => "#/components/schemas/Card",
      "bank" => "#/components/schemas/BankAccount"
    }
  },
  "required" => ["method"]
}
```

With this mapping, `method: "card"` selects `Card` even though the names differ. The `enum` values in `Card` and `BankAccount` then need to be `card` and `bank`.

## Trade-offs

Composition keeps one source of truth for shared fields, and it lets the validator enforce real alternatives. It also makes documents harder to read, and its errors are vaguer. A failed `oneOf` reports `#` as the location, not the field that was wrong.

Skip it when one schema with a few optional properties describes the payload just as well. Composition earns its cost when the shapes really differ, like the card and the bank account above.
