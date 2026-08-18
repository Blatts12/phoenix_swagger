defmodule PhoenixSwagger.ConnValidator do
  @moduledoc """
  Validates a `Plug.Conn` against the spec compiled by `PhoenixSwagger.Validator`.

  Returns:

    * `{:ok, conn}` on success
    * `{:error, :no_matching_path}` if the request path could not be mapped to a schema
    * `{:error, message, path}` if the request was mapped but failed validation
    * `{:error, [{message, path}], path}` if more than one validation error was detected
  """

  alias PhoenixSwagger.Validator

  @doc """
  Validate a request.

  Feel free to use it in your own Plugs.
  """
  def validate(conn) do
    with {:ok, path, operation, root} <- Validator.lookup_request(conn.method, conn.path_info),
         :ok <- Validator.validate_params(root, operation.fragment, path, conn.body_params),
         :ok <- validate_query_params(operation.query_params, conn) do
      {:ok, conn}
    end
  end

  defp validate_query_params(descriptors, conn) do
    descriptors
    |> Enum.map(fn {type, name, required, enum, items} ->
      {type, name, get_param_value(conn.params, name), required, enum, items}
    end)
    |> validate_query_params()
  end

  defp validate_query_params([]), do: :ok

  defp validate_query_params([{_type, _name, nil, required, _, _} | parameters])
       when required in [nil, false] do
    validate_query_params(parameters)
  end

  defp validate_query_params([{_type, name, nil, true, _, _} | _]) do
    {:error, "Required property #{name} was not present.", "#"}
  end

  defp validate_query_params([{_type, name, value, _, enum, _} | parameters])
       when not is_nil(enum) do
    validate_enum(name, value, enum, parameters)
  end

  defp validate_query_params([{"string", _name, _value, _, _, _} | parameters]) do
    validate_query_params(parameters)
  end

  defp validate_query_params([{"integer", name, value, _, _, _} | parameters]) do
    validate_integer(name, value, parameters)
  end

  defp validate_query_params([{"number", name, value, _, _, _} | parameters]) do
    validate_number(name, value, parameters)
  end

  defp validate_query_params([{"boolean", name, value, _, _, _} | parameters]) do
    validate_boolean(name, value, parameters)
  end

  defp validate_query_params([{"array", name, values, _, _, items} | parameters]) do
    validate_array(name, values, items, parameters)
  end

  defp validate_array(name, values, items, parameters) when is_binary(values) do
    validate_array(name, String.split(values, ","), items, parameters)
  end

  defp validate_array(name, values, %{"type" => type} = items, parameters) when is_list(values) do
    case validate_query_params(
           Enum.map(values, &{type, name, &1, false, Map.get(items, "enum"), nil})
         ) do
      :ok -> validate_query_params(parameters)
      error -> error
    end
  end

  defp validate_array(name, _values, _items, _parameters) do
    type_mismatch(name, "Array")
  end

  defp validate_enum(name, value, enum, parameters) do
    if value in enum do
      validate_query_params(parameters)
    else
      {:error, "Value #{inspect(value)} is not allowed in enum.", "#/#{name}"}
    end
  end

  defp validate_boolean(_name, value, parameters) when value in [true, false, "true", "false"] do
    validate_query_params(parameters)
  end

  defp validate_boolean(name, _value, _parameters) do
    type_mismatch(name, "Boolean")
  end

  defp validate_integer(name, value, parameters) when is_binary(value) do
    case Integer.parse(value) do
      {_, ""} -> validate_query_params(parameters)
      _ -> type_mismatch(name, "Integer")
    end
  end

  defp validate_integer(name, _value, _parameters), do: type_mismatch(name, "Integer")

  defp validate_number(name, value, parameters) when is_binary(value) do
    case Float.parse(value) do
      {_, ""} -> validate_query_params(parameters)
      _ -> type_mismatch(name, "Number")
    end
  end

  defp validate_number(name, _value, _parameters), do: type_mismatch(name, "Number")

  defp type_mismatch(name, type) do
    {:error, "Type mismatch. Expected #{type} but got something else.", "#/#{name}"}
  end

  defp get_param_value(params, nested_name) when is_binary(nested_name) do
    get_in_nested(params, Plug.Conn.Query.decode(nested_name))
  end

  defp get_in_nested(nil, _nested_map), do: nil
  defp get_in_nested(params, nil), do: params
  defp get_in_nested(params, ""), do: params

  defp get_in_nested(params, nested_map) when map_size(nested_map) == 1 do
    [{key, child_nested_map}] = Map.to_list(nested_map)

    get_in_nested(params[key], child_nested_map)
  end
end
