defmodule PhoenixSwagger.SchemaTestTest do
  use ExUnit.Case, async: true

  alias PhoenixSwagger.SchemaTest

  @user %{
    "type" => "object",
    "required" => ["email"],
    "properties" => %{"email" => %{"type" => "string"}, "name" => %{"type" => "string"}}
  }

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_schema_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "returns the conn when the body matches the schema", %{path: path} do
    write_schemas!(path, %{"User" => @user})
    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)
    conn = response_conn(%{"email" => "joe@example.com"})

    assert SchemaTest.validate_resp_schema(conn, schema, "User") == conn
  end

  test "flunks with the failing location when the body does not match", %{path: path} do
    write_schemas!(path, %{"User" => @user})
    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        SchemaTest.validate_resp_schema(response_conn(%{"email" => 1}), schema, "User")
      end

    assert error.message =~
             ~r/^Response JSON does not conform to OpenAPI schema from #\/components\/schemas\/User\./

    assert error.message =~ "At #/email:"
  end

  test "flunks when the schema name is unknown", %{path: path} do
    write_schemas!(path, %{"User" => @user})
    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        SchemaTest.validate_resp_schema(response_conn(%{}), schema, "Nope")
      end

    assert error.message =~ ~s(No schema named "Nope" in #/components/schemas)
  end

  test "a type list with null accepts a null body", %{path: path} do
    write_schemas!(path, %{"Pet" => %{"type" => ["string", "null"]}})
    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)
    conn = response_conn(nil)

    assert SchemaTest.validate_resp_schema(conn, schema, "Pet") == conn
  end

  test "reuses the resolved schema while the file is unchanged", %{path: path} do
    write_schemas!(path, %{"Pet" => %{"type" => "string"}})
    {:ok, %{mtime: mtime}} = File.stat(path, time: :posix)
    first = SchemaTest.read_swagger_schema(path)

    write_schemas!(path, %{"Dog" => %{"type" => "string"}})
    File.touch!(path, mtime)

    assert SchemaTest.read_swagger_schema(path) == first
  end

  test "re-reads the file after it changes", %{path: path} do
    write_schemas!(path, %{"Pet" => %{"type" => "string"}})
    {:ok, %{mtime: mtime}} = File.stat(path, time: :posix)
    SchemaTest.read_swagger_schema(path)

    write_schemas!(path, %{"Dog" => %{"type" => "string"}})
    File.touch!(path, mtime + 1)

    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)
    assert Map.has_key?(schema.keys, "Dog")
  end

  defp response_conn(body), do: %Plug.Conn{resp_body: Jason.encode!(body)}

  defp write_schemas!(path, schemas) do
    File.write!(
      path,
      Jason.encode!(%{
        "openapi" => "3.2.0",
        "info" => %{"title" => "Test", "version" => "1.0.0"},
        "components" => %{"schemas" => schemas}
      })
    )
  end
end
