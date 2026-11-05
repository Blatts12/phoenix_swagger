defmodule PhoenixSwagger.SchemaTest do
  @moduledoc """
  Testing helper module that makes it convenient to assert that phoenix controller responses conform to an OpenAPI spec.

  ## Example

      use YourApp.ConnCase
      use PhoenixSwagger.SchemaTest "priv/static/swagger.json"

      test "Get a user by ID", %{conn: conn, swagger_schema: schema} do
        user = Repo.insert! struct(User, @valid_attrs)
        response =
          conn
          |> get(user_path(conn, :show, user))
          |> validate_resp_schema(schema, "UserResponse")
          |> json_response(200)

        assert response["data"]["id"] == user.id
      end

  Errors will be output with the json-path of the location in the response body for the error:

      Response JSON does not conform to OpenAPI schema from #/components/schemas/UserResponse.
      At #/data/name: value is not of type string
      {
        "data": {
          "name": 42,
          "id": 141,
          "email": "foobaz"
        }
      }
  """

  @doc """
  Given a swagger file path, defines an ExUnit `setup_all` block that will
  add the resolved swagger schema to the ExUnit context.
  """
  defmacro __using__(swagger_file) do
    quote do
      @swagger_file unquote(swagger_file)

      import PhoenixSwagger.SchemaTest, only: [validate_resp_schema: 3]

      setup_all _context do
        PhoenixSwagger.SchemaTest.read_swagger_schema(@swagger_file)
      end
    end
  end

  @doc false
  # Every test module that uses this helper calls this in `setup_all`, so
  # cache the resolved schema until the file's mtime or size changes.
  def read_swagger_schema(swagger_file) do
    %{mtime: mtime, size: size} = File.stat!(swagger_file, time: :posix)
    key = {__MODULE__, Path.expand(swagger_file)}

    case :persistent_term.get(key, nil) do
      {{^mtime, ^size}, schema} ->
        [swagger_schema: schema]

      _ ->
        schema = resolve_swagger_schema(swagger_file)
        :persistent_term.put(key, {{mtime, size}, schema})
        [swagger_schema: schema]
    end
  end

  # Builds one JSV key per entry in `components.schemas`, so each test only
  # looks a key up.
  defp resolve_swagger_schema(swagger_file) do
    document = swagger_file |> File.read!() |> PhoenixSwagger.json_library().decode!()
    components = document["components"] || %{}

    {root_key, _normalized, ctx} =
      JSV.build_add!(JSV.build_init!(), %{"components" => components})

    {keys, ctx} =
      Enum.map_reduce(Map.keys(components["schemas"] || %{}), ctx, fn name, ctx ->
        ref = JSV.Ref.parse!("#/components/schemas/#{name}", :root)
        {key, ctx} = JSV.build_key!(ctx, ref)
        {{name, key}, ctx}
      end)

    %{root: JSV.to_root!(ctx, root_key), keys: Map.new(keys)}
  end

  @doc """
  Validates a response body against a schema in `components.schemas`.

  ## Example

      use MyApp.ConnCase
      use PhoenixSwagger.SchemaTest "priv/static/swagger.json"

      test "get user by ID", %{conn: conn, swagger_schema: schema} do
        response =
          conn
          |> get(user_path(conn, :show, 123))
          |> validate_resp_schema(schema, "User")
          |> json_response(200)

        assert response["data"]["id"] == 123
      end
  """
  def validate_resp_schema(conn, %{root: root, keys: keys}, model_name) do
    response_data = conn.resp_body |> PhoenixSwagger.json_library().decode!()

    key =
      Map.get_lazy(keys, model_name, fn ->
        ExUnit.Assertions.flunk(~s(No schema named "#{model_name}" in #/components/schemas))
      end)

    case PhoenixSwagger.Validator.validate_value_against_key(root, key, response_data) do
      :ok ->
        conn

      {:error, errors} ->
        headline =
          "Response JSON does not conform to OpenAPI schema from #/components/schemas/#{model_name}."

        error_details =
          errors
          |> Enum.map(fn {msg, path} -> "At #{path}: #{msg}" end)
          |> Enum.join("\n")

        response_pretty = PhoenixSwagger.json_library().encode!(response_data, pretty: true)
        message = Enum.join([headline, error_details, response_pretty], "\n")
        ExUnit.Assertions.flunk(message)
    end
  end
end
