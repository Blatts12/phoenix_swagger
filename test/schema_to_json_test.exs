defmodule PhoenixSwagger.SchemaToJsonTest do
  use ExUnit.Case, async: true
  alias PhoenixSwagger.Schema
  import PhoenixSwagger, only: [to_json: 1]

  test "ref points at components.schemas" do
    assert to_json(Schema.ref(:User)) == %{"$ref" => "#/components/schemas/User"}
  end

  test "nullable adds null to the type" do
    assert to_json(Schema.nullable(%Schema{type: :string}, true)) ==
             %{"type" => ["string", "null"]}

    assert to_json(Schema.nullable(%Schema{type: [:string, :integer]}, true)) ==
             %{"type" => ["string", "integer", "null"]}

    assert to_json(Schema.nullable(%Schema{type: [:string, :null]}, true)) ==
             %{"type" => ["string", "null"]}
  end

  test "nullable ref becomes anyOf with null" do
    assert to_json(Schema.nullable(Schema.ref(:User), true)) == %{
             "anyOf" => [%{"$ref" => "#/components/schemas/User"}, %{"type" => "null"}]
           }
  end

  test "nullable enum accepts null" do
    schema = %Schema{type: :string, enum: [:asc, :desc]} |> Schema.nullable(true)

    assert to_json(schema) == %{
             "type" => ["string", "null"],
             "enum" => ["asc", "desc", nil]
           }
  end

  test "nullable property option" do
    json =
      to_json(Schema.property(%Schema{type: :object}, :phone, :string, "Phone", nullable: true))

    assert json["properties"]["phone"] == %{
             "type" => ["string", "null"],
             "description" => "Phone"
           }
  end

  test "numeric exclusive bounds" do
    assert to_json(Schema.exclusive_maximum(%Schema{type: :number}, 10)) ==
             %{"type" => "number", "exclusiveMaximum" => 10}
  end

  test "legacy boolean exclusive bounds move the limit" do
    schema = %Schema{type: :number} |> Schema.maximum(128) |> Schema.exclusive_maximum(true)
    assert to_json(schema) == %{"type" => "number", "exclusiveMaximum" => 128}

    schema = %Schema{type: :number} |> Schema.minimum(16) |> Schema.exclusive_minimum(false)
    assert to_json(schema) == %{"type" => "number", "minimum" => 16}
  end

  test "tuple items become prefixItems" do
    schema =
      Schema.items(%Schema{type: :array}, [%Schema{type: :string}, %Schema{type: :number}])

    assert to_json(schema) == %{
             "type" => "array",
             "prefixItems" => [%{"type" => "string"}, %{"type" => "number"}]
           }
  end

  test "nullable composition becomes anyOf with null" do
    schema = %Schema{allOf: [Schema.ref(:Pet)], description: "Owner pet"} |> Schema.nullable(true)

    assert to_json(schema) == %{
             "description" => "Owner pet",
             "anyOf" => [
               %{"allOf" => [%{"$ref" => "#/components/schemas/Pet"}]},
               %{"type" => "null"}
             ]
           }
  end

  test "one_of and any_of render their keywords" do
    one_of = Schema.one_of(%Schema{}, [Schema.ref(:Card), Schema.ref(:BankAccount)])
    any_of = Schema.any_of(%Schema{}, [%Schema{type: :string}, %Schema{type: :integer}])

    assert to_json(one_of) == %{
             "oneOf" => [
               %{"$ref" => "#/components/schemas/Card"},
               %{"$ref" => "#/components/schemas/BankAccount"}
             ]
           }

    assert to_json(any_of) == %{"anyOf" => [%{"type" => "string"}, %{"type" => "integer"}]}
  end

  test "nullable typed composition keeps type and discriminator inside the non-null branch" do
    schema =
      %Schema{type: :object, title: "Payment"}
      |> Schema.one_of([Schema.ref(:Card), Schema.ref(:BankAccount)])
      |> Schema.discriminator(:method)
      |> Schema.nullable(true)

    assert to_json(schema) == %{
             "title" => "Payment",
             "anyOf" => [
               %{
                 "type" => "object",
                 "oneOf" => [
                   %{"$ref" => "#/components/schemas/Card"},
                   %{"$ref" => "#/components/schemas/BankAccount"}
                 ],
                 "discriminator" => %{"propertyName" => "method"},
                 "required" => ["method"]
               },
               %{"type" => "null"}
             ]
           }
  end

  test "nullable untyped enum accepts null" do
    assert to_json(Schema.nullable(%Schema{enum: [:a]}, true)) == %{"enum" => ["a", nil]}
  end

  test "discriminator becomes a Discriminator Object" do
    json = to_json(%Schema{type: :object} |> Schema.discriminator(:pet_type))
    assert json["discriminator"] == %{"propertyName" => "pet_type"}
    assert json["required"] == ["pet_type"]
  end
end
