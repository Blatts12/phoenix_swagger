defmodule PhoenixSwagger.Validator do
  @moduledoc """
  Compiles OpenAPI 3.1 and 3.2 documents into a `JSV` root for request validation.

  Call `parse_swagger_schema/1` once at application start. It reads the documents,
  builds every schema the validator needs a single time, and stores the JSV root,
  query-parameter descriptors, and a path trie in `:persistent_term`.

  Then use `validate/2` with a resource path and parameters, or
  `PhoenixSwagger.ConnValidator.validate/1` / `PhoenixSwagger.Plug.Validate`
  on a connection.
  """

  @http_methods ~w(get put post delete options head patch trace query)
  @state_key {__MODULE__, :default}
  @supported_openapi_version ~r/^3\.[12]\.\d+/
  @form_media_types ["application/x-www-form-urlencoded", "multipart/form-data"]
  @validator_schemas_key "x-phoenix-swagger-schemas"
  # Keywords that never fail a value under JSON Schema 2020-12 defaults, plus
  # `type` and `enum`, which `PhoenixSwagger.ConnValidator` checks itself.
  @keys_checked_without_jsv ~w(type enum description title example examples default format
                               deprecated readOnly writeOnly contentMediaType contentEncoding)

  # Errors whose only job is to say a child failed. The child error carries the
  # useful message and location, so these are dropped when flattening.
  @wrapper_error_kinds [
    :properties,
    :items,
    :prefixItems,
    :additionalProperties,
    :patternProperties,
    :dependentSchemas,
    :propertyNames,
    :contains,
    :"$ref",
    :"$dynamicRef"
  ]

  @doc """
  Parses one or more OpenAPI documents, builds them once, and stores the result
  in `:persistent_term`.

  Multiple files are merged (paths and `components`). Each operation keeps the
  base path of the first `servers` entry of the file it came from. A later call
  replaces the previously compiled documents.

  Returns a list of `{path, %{schema: schema}}` tuples, where `path` is the
  resource path (`"/get/pets"`) and `schema` is the request schema checked by
  `validate/2`.
  """
  def parse_swagger_schema(specs) when is_list(specs) do
    specs
    |> Enum.map(&read_openapi_document!/1)
    |> compile_documents()
  end

  def parse_swagger_schema(spec), do: parse_swagger_schema([spec])

  @doc """
  Validates `params` against the compiled schema for `path`.

  Returns `:ok` when the parameters are valid, or:

    * `{:error, :resource_not_exists}` when `path` is not in the compiled spec
    * `{:error, error_message, path}` when one parameter is invalid
    * `{:error, [{error_message, path}], resource_path}` when several are invalid
  """
  def validate(path, params) do
    case lookup(path) do
      {:ok, root, %{body_key: body_key}} ->
        validate_params(root, body_key, path, params)

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
  def validate_params(root, key, path, params) do
    case validate_value_against_key(root, key, params) do
      :ok -> :ok
      {:error, [{error, error_path}]} -> {:error, error, error_path}
      {:error, errors} -> {:error, errors, path}
    end
  end

  @doc false
  def validate_value_against_key(root, key, value) do
    case JSV.validate(value, root, key: key) do
      {:ok, _casted} -> :ok
      {:error, error} -> {:error, flatten_jsv_errors(error)}
    end
  end

  @doc false
  # JSV reports each failing keyword with its instance location. Keep the leaf
  # errors and look inside `allOf`, since every branch of it must hold.
  def flatten_jsv_errors(error) do
    details = JSV.normalize_error(error).details

    case flatten_error_details(details) do
      [] ->
        for detail <- details,
            entry <- detail.errors,
            do: {entry.message, detail.instanceLocation}

      errors ->
        Enum.uniq(errors)
    end
  end

  defp flatten_error_details(details) do
    Enum.flat_map(details, fn detail ->
      Enum.flat_map(Map.get(detail, :errors, []), fn
        %{kind: :allOf, details: nested} -> flatten_error_details(nested)
        %{kind: kind} when kind in @wrapper_error_kinds -> []
        %{message: message} -> [{message, detail.instanceLocation}]
      end)
    end)
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

  defp compile_documents(documents) do
    components =
      documents
      |> Enum.map(&(&1["components"] || %{}))
      |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _type, a, b -> Map.merge(a, b) end))

    # A path declared in several files keeps the last declaration.
    raw_operations =
      documents
      |> Enum.flat_map(&list_operations(&1, components))
      |> Map.new()
      |> Map.to_list()

    {schemas, operations} = index_validator_schemas(raw_operations)
    {root, keys} = build_jsv_root(components, schemas)

    operations =
      Map.new(operations, fn {path, operation} ->
        {path,
         %{
           body_key: keys[operation.schema_index],
           parameters:
             Enum.map(operation.parameters, fn parameter ->
               parameter
               |> Map.put(:constraints_key, keys[parameter.constraints_index])
               |> Map.delete(:constraints_index)
             end)
         }}
      end)

    trie =
      Enum.reduce(raw_operations, %{}, fn {path, %{base_path: base_path}}, trie ->
        put_path(trie, route_segments(base_path, path), path)
      end)

    :persistent_term.put(@state_key, %{root: root, operations: operations, trie: trie})

    Enum.map(raw_operations, fn {path, %{schema: schema}} -> {path, %{schema: schema}} end)
  end

  # Every schema JSV checks lives in one root, so `$ref`s to `components`
  # resolve. Operation and parameter schemas sit in a list under a private key
  # and are addressed by index.
  defp index_validator_schemas(raw_operations) do
    {operations, {schemas, _count}} =
      Enum.map_reduce(raw_operations, {[], 0}, fn {path, operation}, acc ->
        {parameters, {schemas, count}} =
          Enum.map_reduce(operation.parameters, acc, &index_parameter_constraints/2)

        {{path, %{schema_index: count, parameters: parameters}},
         {[operation.schema | schemas], count + 1}}
      end)

    {Enum.reverse(schemas), operations}
  end

  defp index_parameter_constraints(%{constraints: nil} = parameter, acc) do
    {parameter |> Map.delete(:constraints) |> Map.put(:constraints_index, nil), acc}
  end

  defp index_parameter_constraints(parameter, {schemas, count}) do
    {parameter |> Map.delete(:constraints) |> Map.put(:constraints_index, count),
     {[parameter.constraints | schemas], count + 1}}
  end

  defp build_jsv_root(components, schemas) do
    {root_key, _normalized, ctx} =
      JSV.build_add!(JSV.build_init!(), %{
        "components" => components,
        @validator_schemas_key => schemas
      })

    {keys, ctx} =
      schemas
      |> Enum.with_index()
      |> Enum.map_reduce(ctx, fn {_schema, index}, ctx ->
        ref = JSV.Ref.parse!("#/#{@validator_schemas_key}/#{index}", :root)
        {key, ctx} = JSV.build_key!(ctx, ref)
        {{index, key}, ctx}
      end)

    {JSV.to_root!(ctx, root_key), Map.new(keys)}
  end

  defp list_operations(document, components) do
    base_path = find_base_path(document["servers"])

    for {path, path_item} <- document["paths"] || %{},
        {method, operation} <- path_item,
        method in @http_methods do
      parameters =
        merge_path_item_parameters(path_item["parameters"], operation["parameters"], components)

      request_body = resolve_reference(operation["requestBody"], components)
      {body_schema, form_schema} = pick_request_body_schemas(request_body, components)

      {"/" <> method <> path,
       %{
         schema: synthesize_schema(parameters, body_schema, form_schema),
         parameters: parameter_descriptors(parameters) ++ form_descriptors(form_schema),
         base_path: base_path
       }}
    end
  end

  # Path Item parameters apply to every operation. An operation parameter with
  # the same name and location replaces one from the Path Item.
  defp merge_path_item_parameters(path_item_parameters, operation_parameters, components) do
    ((path_item_parameters || []) ++ (operation_parameters || []))
    |> Enum.map(&resolve_reference(&1, components))
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1["name"], &1["in"]})
    |> Enum.reverse()
  end

  # Components may hold Parameter and Request Body Objects referenced by `$ref`.
  defp resolve_reference(%{"$ref" => "#/components/" <> pointer}, components) do
    case get_in(components, String.split(pointer, "/")) do
      nil -> raise ArgumentError, "unknown reference #/components/#{pointer}"
      target -> target
    end
  end

  defp resolve_reference(value, _components), do: value

  # The first server's path is the base path. Variables take their defaults,
  # and no servers means "/", as the spec says.
  defp find_base_path([%{"url" => url} = server | _]) do
    url
    |> String.replace(~r/\{([^}]+)\}/, fn template ->
      name = String.slice(template, 1..-2//1)
      get_in(server, ["variables", name, "default"]) || ""
    end)
    |> URI.parse()
    |> Map.get(:path)
    |> Kernel.||("/")
  end

  defp find_base_path(_servers), do: "/"

  defp pick_request_body_schemas(%{"content" => content}, components) when is_map(content) do
    json = Enum.find(content, fn {media_type, _} -> json_media_type?(media_type) end)
    form = Enum.find(content, fn {media_type, _} -> media_type in @form_media_types end)

    case {json, form} do
      {{_, %{"schema" => schema}}, _form} -> {inline_component_schema(schema, components), nil}
      {_json, {_, %{"schema" => schema}}} -> {nil, inline_component_schema(schema, components)}
      _ -> {nil, nil}
    end
  end

  defp pick_request_body_schemas(_request_body, _components), do: {nil, nil}

  defp json_media_type?(media_type) do
    media_type == "application/json" or String.ends_with?(media_type, "+json")
  end

  defp inline_component_schema(%{"$ref" => "#/components/schemas/" <> name}, components) do
    case components do
      %{"schemas" => %{^name => schema}} -> schema
      _ -> raise ArgumentError, "request body references unknown schema #{inspect(name)}"
    end
  end

  defp inline_component_schema(schema, _components) when is_map(schema), do: schema

  # `validate/2` gets one map of typed values. Query and path values go in as
  # properties next to a JSON body. Headers never reach the params map. Form
  # fields arrive as strings, so only string and untyped (file) fields fit here.
  # `PhoenixSwagger.ConnValidator` parses and checks the rest.
  defp synthesize_schema(parameters, body_schema, form_schema) do
    properties =
      for parameter <- parameters,
          parameter["in"] in ["query", "path"],
          into: %{},
          do: {parameter["name"], parameter["schema"] || %{}}

    form_properties =
      for {name, schema} <- (form_schema || %{})["properties"] || %{},
          schema["type"] in [nil, "string"],
          into: %{},
          do: {name, schema}

    schema = Map.put_new(body_schema || %{}, "type", "object")

    case Map.merge(properties, form_properties) do
      empty when empty == %{} -> schema
      extra -> Map.update(schema, "properties", extra, &Map.merge(&1, extra))
    end
  end

  defp parameter_descriptors(parameters) do
    for parameter <- parameters,
        parameter["in"] in ["query", "path", "header"],
        not ignored_header_parameter?(parameter) do
      build_descriptor(parameter["name"], parameter["in"], parameter["schema"] || %{}, parameter)
    end
  end

  # The spec says header parameters with these names "SHALL be ignored".
  defp ignored_header_parameter?(%{"in" => "header", "name" => name}),
    do: String.downcase(name) in ["accept", "content-type", "authorization"]

  defp ignored_header_parameter?(_parameter), do: false

  defp form_descriptors(nil), do: []

  defp form_descriptors(form_schema) do
    required = form_schema["required"] || []

    for {name, schema} <- form_schema["properties"] || %{} do
      build_descriptor(name, "form", schema, %{"required" => name in required})
    end
  end

  defp build_descriptor(name, location, schema, parameter) do
    %{
      name: name,
      in: location,
      type: schema["type"],
      items: schema["items"],
      enum: schema["enum"],
      required: parameter["required"] == true,
      style: parameter["style"] || default_style(location),
      explode:
        Map.get(parameter, "explode", (parameter["style"] || default_style(location)) == "form"),
      key_path: parameter_key_path(location, name),
      constraints: find_constraints(schema)
    }
  end

  defp default_style("query"), do: "form"
  defp default_style("form"), do: "form"
  defp default_style(_location), do: "simple"

  # Plug lowercases header names. Other names may use bracket syntax, such
  # as `page[size]`, so decode them once here instead of on every request.
  defp parameter_key_path("header", name), do: [String.downcase(name)]

  defp parameter_key_path(_location, name) do
    name |> Plug.Conn.Query.decode() |> collect_query_keys()
  end

  defp collect_query_keys(decoded) when is_map(decoded) and map_size(decoded) == 1 do
    [{key, nested}] = Map.to_list(decoded)
    [key | collect_query_keys(nested)]
  end

  defp collect_query_keys(_decoded), do: []

  # `nil` lets the request path skip JSON Schema entirely for the common case
  # of a parameter with a type and nothing else. `type` and `enum` are left out
  # because `PhoenixSwagger.ConnValidator` parses the raw string into the type
  # and checks `enum` with a clearer message, as it does for array items.
  defp find_constraints(schema) do
    constraints =
      schema
      |> Map.drop(@keys_checked_without_jsv)
      |> drop_item_checks_done_by_parsing()

    if map_size(constraints) == 0, do: nil, else: constraints
  end

  defp drop_item_checks_done_by_parsing(%{"items" => items} = constraints) when is_map(items) do
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

  # `trim: true` drops the empty segments a `/` base path or a trailing slash
  # would add, since `conn.path_info` never contains them.
  defp route_segments(base_path, "/" <> rest) do
    [method | path_segments] = String.split(rest, "/", trim: true)
    [method | String.split(base_path, "/", trim: true) ++ path_segments]
  end

  defp read_openapi_document!(file) do
    document =
      file
      |> File.read!()
      |> decode_openapi_document!(file)

    unless is_binary(document["openapi"]) and document["openapi"] =~ @supported_openapi_version do
      raise ArgumentError,
            "#{file} is not an OpenAPI 3.1 or 3.2 document " <>
              "(openapi: #{inspect(document["openapi"])}, swagger: #{inspect(document["swagger"])})"
    end

    Map.take(document, ["servers", "paths", "components"])
  end

  defp decode_openapi_document!(contents, file) do
    PhoenixSwagger.json_library().decode!(contents)
  rescue
    e ->
      reraise ArgumentError,
              [message: "invalid JSON in swagger schema #{file}: #{Exception.message(e)}"],
              __STACKTRACE__
  end
end
