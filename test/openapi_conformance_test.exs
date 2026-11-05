defmodule PhoenixSwagger.OpenApiConformanceTest do
  use ExUnit.Case, async: true
  import PhoenixSwagger.OpenApiConformance

  @info %{"title" => "Pets", "version" => "1.0.0"}

  test "accepts a minimal OpenAPI 3.2 document" do
    assert :ok =
             assert_valid_openapi_document(%{
               "openapi" => "3.2.0",
               "info" => @info,
               "paths" => %{}
             })
  end

  test "rejects a Swagger 2.0 document" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_valid_openapi_document(%{"swagger" => "2.0", "info" => @info, "paths" => %{}})
    end
  end

  test "JSV ignores OAS-only keywords" do
    assert {:ok, _root} =
             JSV.build(%{
               "type" => "object",
               "discriminator" => %{"propertyName" => "kind"},
               "example" => %{}
             })
  end

  test "JSV validates against a components.schemas pointer" do
    document = %{
      "components" => %{
        "schemas" => %{
          "Pet" => %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
        }
      }
    }

    {root_key, _normalized, ctx} = JSV.build_add!(JSV.build_init!(), document)
    {pet_key, ctx} = JSV.build_key!(ctx, JSV.Ref.parse!("#/components/schemas/Pet", :root))
    root = JSV.to_root!(ctx, root_key)

    assert {:ok, _} = JSV.validate(%{"name" => "Rex"}, root, key: pet_key)
    assert {:error, error} = JSV.validate(%{"name" => 1}, root, key: pet_key)
    assert inspect(JSV.normalize_error(error)) =~ "/name"
  end
end
