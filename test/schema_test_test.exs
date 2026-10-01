defmodule PhoenixSwagger.SchemaTestTest do
  use ExUnit.Case, async: true

  alias PhoenixSwagger.SchemaTest

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_schema_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "converts x-nullable definitions", %{path: path} do
    write_definitions!(path, %{"Pet" => %{"type" => "string", "x-nullable" => true}})

    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)

    assert schema.schema["definitions"]["Pet"]["type"] == ["string", "null"]
  end

  test "reuses the resolved schema while the file is unchanged", %{path: path} do
    write_definitions!(path, %{"Pet" => %{"type" => "string"}})
    {:ok, %{mtime: mtime}} = File.stat(path, time: :posix)
    first = SchemaTest.read_swagger_schema(path)

    write_definitions!(path, %{"Dog" => %{"type" => "string"}})
    File.touch!(path, mtime)

    assert SchemaTest.read_swagger_schema(path) == first
  end

  test "re-reads the file after it changes", %{path: path} do
    write_definitions!(path, %{"Pet" => %{"type" => "string"}})
    {:ok, %{mtime: mtime}} = File.stat(path, time: :posix)
    SchemaTest.read_swagger_schema(path)

    write_definitions!(path, %{"Dog" => %{"type" => "string"}})
    File.touch!(path, mtime + 1)

    [swagger_schema: schema] = SchemaTest.read_swagger_schema(path)
    assert Map.has_key?(schema.schema["definitions"], "Dog")
  end

  defp write_definitions!(path, definitions) do
    File.write!(path, Jason.encode!(%{"swagger" => "2.0", "definitions" => definitions}))
  end
end
