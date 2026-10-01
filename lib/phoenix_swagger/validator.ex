defmodule PhoenixSwagger.Validator do
  @moduledoc """
  Converts a Swagger schema into an `ex_json_schema` structure for request validation.

  Call `parse_swagger_schema/1` once at application start. It reads the spec,
  resolves definitions a single time, and stores fragments, query-parameter
  descriptors, and a path trie in `:persistent_term`.

  Then use `validate/2` with a resource path and parameters, or
  `PhoenixSwagger.ConnValidator.validate/1` / `PhoenixSwagger.Plug.Validate`
  on a connection.
  """

  @http_methods ~w(get put post delete options head patch)
  @state_key {__MODULE__, :default}

  # Swagger 2 parameter keywords that JSON Schema can check once a raw
  # query, path, header, or form value is parsed into its declared type.
  @constraint_keys ~w(format maximum exclusiveMaximum minimum exclusiveMinimum maxLength
                      minLength pattern maxItems minItems uniqueItems enum multipleOf items)
  @draft4 "http://json-schema.org/draft-04/schema#"

  @doc """
  Parses one or more Swagger schema files, resolves them once, and stores the
  result in `:persistent_term`.

  Multiple files are merged (paths and definitions). Each operation keeps the
  `basePath` from the file it came from. A later call replaces the previously
  compiled spec.

  Returns a list of `{path, %{schema: fragment}}` tuples, where `path` is the
  resource path (`"/get/pets"`) and `fragment` is the resolved request schema.
  """
  def parse_swagger_schema(specs) when is_list(specs) do
    specs
    |> Enum.map(&read_swagger_schema/1)
    |> compile_schemas()
  end

  def parse_swagger_schema(spec), do: parse_swagger_schema([spec])

  @doc """
  Validates `params` against the compiled schema for `path`.

  Returns `:ok` when the parameters are valid, or:

    * `{:error, :resource_not_exists}` when `path` is not in the compiled spec
    * `{:error, error_message, path}` when at least one parameter is invalid
  """
  def validate(path, params) do
    case lookup(path) do
      {:ok, root, %{fragment: fragment}} ->
        validate_params(root, fragment, path, params)

      :error ->
        {:error, :resource_not_exists}
    end
  end

  @doc false
  def lookup_request(method, path_info) do
    state = get_state()
    segments = [method |> to_string() |> String.downcase() | path_info]

    case walk(state.trie, segments) do
      nil ->
        {:error, :no_matching_path}

      path ->
        {:ok, path, Map.fetch!(state.operations, path), state.root}
    end
  end

  @doc false
  def validate_params(root, fragment, path, params) do
    case ExJsonSchema.Validator.validate_fragment(root, fragment, params) do
      :ok ->
        :ok

      {:error, [{error, error_path}]} ->
        {:error, error, error_path}

      {:error, errors} ->
        {:error, errors, path}
    end
  end

  @doc false
  def clear do
    :persistent_term.erase(@state_key)
    :ok
  end

  defp lookup(path) do
    case get_state() do
      %{operations: %{^path => operation}, root: root} ->
        {:ok, root, operation}

      _ ->
        :error
    end
  end

  defp get_state do
    :persistent_term.get(@state_key, %{root: nil, operations: %{}, trie: %{}})
  end

  defp compile_schemas(schemas) do
    definitions =
      schemas
      |> Enum.map(&(&1["definitions"] || %{}))
      |> Enum.reduce(%{}, fn defs, acc -> Map.merge(acc, defs) end)
      |> swagger_nullable_to_json_schema()

    raw_operations =
      schemas
      |> Enum.flat_map(&operations_from_schema(&1, definitions))
      |> Map.new()

    root =
      ExJsonSchema.Schema.resolve(%{
        "definitions" => definitions,
        "paths" => Map.new(raw_operations, fn {path, %{schema: schema}} -> {path, schema} end)
      })

    operations =
      Map.new(raw_operations, fn {path, %{parameters: parameters}} ->
        {path, %{fragment: root.schema["paths"][path], parameters: parameters}}
      end)

    trie =
      Enum.reduce(raw_operations, %{}, fn {path, %{base_path: base_path}}, trie ->
        put_path(trie, route_segments(base_path, path), path)
      end)

    :persistent_term.put(@state_key, %{root: root, operations: operations, trie: trie})

    Enum.map(operations, fn {path, %{fragment: fragment}} ->
      {path, %{schema: fragment}}
    end)
  end

  defp operations_from_schema(schema, definitions) do
    base_path = schema["basePath"]

    for {path, path_item} <- schema["paths"] || %{},
        {method, operation} <- path_item,
        method in @http_methods do
      parameters = operation["parameters"] || []
      resource_path = "/" <> method <> path
      schema_object = synthesize_schema(parameters, definitions)

      {resource_path,
       %{
         schema: schema_object,
         parameters: parameter_descriptors(parameters),
         base_path: base_path
       }}
    end
  end

  defp synthesize_schema(parameters, definitions) do
    {schema, properties} =
      Enum.reduce(parameters, {%{}, %{}}, fn parameter, {schema, properties} ->
        cond do
          is_nil(parameter["type"]) ->
            {Map.merge(schema, body_schema(parameter["schema"], definitions)), properties}

          checked_by_json_schema?(parameter) ->
            {schema, Map.put(properties, parameter["name"], parameter_schema(parameter))}

          true ->
            {schema, properties}
        end
      end)

    schema = Map.put_new(schema, "type", "object")

    if properties == %{} do
      schema
    else
      Map.update(schema, "properties", properties, &Map.merge(&1, properties))
    end
  end

  defp body_schema(%{"$ref" => "#/definitions/" <> name}, definitions) do
    case definitions do
      %{^name => definition} -> definition
      _ -> raise ArgumentError, "body parameter references unknown definition #{inspect(name)}"
    end
  end

  defp body_schema(inline_schema, _definitions) when is_map(inline_schema) do
    swagger_nullable_to_json_schema(inline_schema)
  end

  # Headers never reach the params map, and form fields arrive as strings, so
  # only string and file form fields can be checked as JSON types. The rest are
  # parsed and checked by `PhoenixSwagger.ConnValidator`.
  defp checked_by_json_schema?(%{"in" => "header"}), do: false

  defp checked_by_json_schema?(%{"in" => "formData", "type" => type}),
    do: type in ["file", "string"]

  defp checked_by_json_schema?(_parameter), do: true

  # Swagger 2's `file` type is valid on formData parameters, but JSON Schema
  # has no such type. Leave the public specification unchanged and accept an
  # unconstrained object here so multipart uploads reach domain validation.
  defp parameter_schema(%{"in" => "formData", "type" => "file"}) do
    %{"type" => "object"}
  end

  defp parameter_schema(parameter) do
    Map.take(parameter, ["type" | @constraint_keys])
  end

  defp parameter_descriptors(parameters) do
    for parameter <- parameters,
        parameter["type"] != nil,
        parameter["in"] in ["query", "path", "header", "formData"] do
      %{
        name: parameter["name"],
        in: parameter["in"],
        type: parameter["type"],
        items: parameter["items"],
        enum: parameter["enum"],
        required: parameter["required"] == true,
        key_path: parameter_key_path(parameter),
        constraints: resolve_constraints(parameter)
      }
    end
  end

  # Plug lowercases header names. Other names may use bracket syntax, such
  # as `page[size]`, so decode them once here instead of on every request.
  defp parameter_key_path(%{"in" => "header", "name" => name}), do: [String.downcase(name)]

  defp parameter_key_path(%{"name" => name}) do
    name |> Plug.Conn.Query.decode() |> collect_query_keys()
  end

  defp collect_query_keys(decoded) when is_map(decoded) and map_size(decoded) == 1 do
    [{key, nested}] = Map.to_list(decoded)
    [key | collect_query_keys(nested)]
  end

  defp collect_query_keys(_decoded), do: []

  # `nil` lets the request path skip JSON Schema entirely for the common
  # case of a parameter declared with a type and nothing else. `enum` is left
  # out because `PhoenixSwagger.ConnValidator` checks it with a clearer message,
  # as it does the `type` and `enum` of array items.
  defp resolve_constraints(parameter) do
    constraints =
      parameter
      |> Map.take(@constraint_keys -- ["enum"])
      |> drop_item_checks_done_by_parsing()

    if map_size(constraints) == 0 do
      nil
    else
      constraints |> Map.put("$schema", @draft4) |> ExJsonSchema.Schema.resolve()
    end
  end

  defp drop_item_checks_done_by_parsing(%{"items" => items} = constraints) do
    case Map.drop(items, ["type", "enum"]) do
      remaining when map_size(remaining) == 0 -> Map.delete(constraints, "items")
      remaining -> Map.put(constraints, "items", remaining)
    end
  end

  defp drop_item_checks_done_by_parsing(constraints), do: constraints

  # Prefer an exact segment match; fall back to a templated `{param}` branch
  # and backtrack if the exact branch dead-ends.
  defp put_path(node, [], path), do: Map.put(node, :leaf, path)

  defp put_path(node, ["{" <> _ | rest], path) do
    Map.update(node, :_, put_path(%{}, rest, path), &put_path(&1, rest, path))
  end

  defp put_path(node, [segment | rest], path) do
    Map.update(node, segment, put_path(%{}, rest, path), &put_path(&1, rest, path))
  end

  defp walk(node, []), do: Map.get(node, :leaf)

  defp walk(node, [segment | rest]) do
    case node do
      %{^segment => subtree} -> walk(subtree, rest) || walk_placeholder(node, rest)
      _ -> walk_placeholder(node, rest)
    end
  end

  defp walk_placeholder(%{_: subtree}, rest), do: walk(subtree, rest)
  defp walk_placeholder(_node, _rest), do: nil

  # `trim: true` drops the empty segments a `/` basePath or a trailing slash
  # would add, since `conn.path_info` never contains them.
  defp route_segments(base_path, "/" <> rest) do
    [method | path_segments] = String.split(rest, "/", trim: true)
    [method | String.split(base_path || "", "/", trim: true) ++ path_segments]
  end

  @doc false
  # Swagger 2.0 and JSON Schema differ in the treatment of nulls.
  # When the "x-nullable" vendor extension is present, convert the type to
  # an array including "null".
  def swagger_nullable_to_json_schema(schema = %{"type" => type, "x-nullable" => true})
      when is_binary(type) do
    schema
    |> Map.put("type", [type, "null"])
    |> swagger_nullable_to_json_schema()
  end

  def swagger_nullable_to_json_schema(schema = %{"$ref" => ref, "x-nullable" => true})
      when is_binary(ref) do
    schema
    |> Map.drop(["$ref", "x-nullable"])
    |> Map.put("oneOf", [%{"type" => "null"}, %{"$ref" => ref}])
    |> swagger_nullable_to_json_schema()
  end

  def swagger_nullable_to_json_schema(schema) when is_map(schema) do
    Map.new(schema, fn {k, v} -> {k, swagger_nullable_to_json_schema(v)} end)
  end

  def swagger_nullable_to_json_schema(schema) when is_list(schema) do
    Enum.map(schema, &swagger_nullable_to_json_schema/1)
  end

  def swagger_nullable_to_json_schema(other), do: other

  defp read_swagger_schema(file) do
    schema =
      file
      |> File.read!()
      |> decode_swagger_schema!(file)

    Map.take(schema, ["basePath", "paths", "definitions"])
  end

  defp decode_swagger_schema!(contents, file) do
    PhoenixSwagger.json_library().decode!(contents)
  rescue
    e ->
      reraise ArgumentError,
              [message: "invalid JSON in swagger schema #{file}: #{Exception.message(e)}"],
              __STACKTRACE__
  end
end
