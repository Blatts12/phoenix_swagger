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
         :ok <- validate_parameters(operation.parameters, conn) do
      {:ok, conn}
    end
  end

  defp validate_parameters([], _conn), do: :ok

  defp validate_parameters([parameter | parameters], conn) do
    case validate_parameter(parameter, fetch_parameter_value(parameter, conn)) do
      :ok -> validate_parameters(parameters, conn)
      error -> error
    end
  end

  defp validate_parameter(%{required: true, name: name}, nil) do
    {:error, "Required property #{name} was not present.", "#"}
  end

  defp validate_parameter(_parameter, nil), do: :ok

  defp validate_parameter(parameter, value) do
    with {:ok, parsed} <- parse_parameter_value(parameter, value) do
      check_parameter_constraints(parameter, parsed)
    end
  end

  defp fetch_parameter_value(%{in: "header", key_path: [header]}, conn) do
    case Plug.Conn.get_req_header(conn, header) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp fetch_parameter_value(%{key_path: key_path}, conn) do
    Enum.reduce(key_path, conn.params, fn
      key, %{} = params -> Map.get(params, key)
      _key, _value -> nil
    end)
  end

  defp parse_parameter_value(%{type: "array", name: name}, value)
       when not is_binary(value) and not is_list(value) do
    type_mismatch(name, "Array")
  end

  defp parse_parameter_value(%{type: "array", name: name, items: items}, value) do
    items = items || %{}

    value
    |> split_array_value()
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, parsed} ->
      case parse_scalar_value(name, items["type"], items["enum"], item) do
        {:ok, item} -> {:cont, {:ok, [item | parsed]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_parameter_value(%{type: type, name: name, enum: enum}, value) do
    parse_scalar_value(name, type, enum, value)
  end

  defp split_array_value(value) when is_binary(value), do: String.split(value, ",")
  defp split_array_value(value) when is_list(value), do: value

  defp parse_scalar_value(name, type, enum, value) do
    case cast_value(type, value) do
      {:ok, parsed} -> check_enum(name, enum, parsed)
      {:error, expected_type} -> type_mismatch(name, expected_type)
    end
  end

  # Query, path, header, and form values arrive as strings. JSON bodies may
  # also fill `conn.params`, so values already of the declared type pass.
  defp cast_value("integer", value) when is_integer(value), do: {:ok, value}

  defp cast_value("integer", value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "Integer"}
    end
  end

  defp cast_value("integer", _value), do: {:error, "Integer"}
  defp cast_value("number", value) when is_number(value), do: {:ok, value}

  defp cast_value("number", value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "Number"}
    end
  end

  defp cast_value("number", _value), do: {:error, "Number"}
  defp cast_value("boolean", value) when is_boolean(value), do: {:ok, value}
  defp cast_value("boolean", "true"), do: {:ok, true}
  defp cast_value("boolean", "false"), do: {:ok, false}
  defp cast_value("boolean", _value), do: {:error, "Boolean"}

  # `string`, `file`, and array items without a declared type stay as sent.
  defp cast_value(_type, value), do: {:ok, value}

  defp check_enum(_name, nil, value), do: {:ok, value}

  defp check_enum(name, enum, value) do
    if value in enum do
      {:ok, value}
    else
      {:error, "Value #{inspect(value)} is not allowed in enum.", "#/#{name}"}
    end
  end

  defp check_parameter_constraints(%{constraints: nil}, _value), do: :ok

  defp check_parameter_constraints(%{constraints: constraints, name: name}, value) do
    case ExJsonSchema.Validator.validate(constraints, value) do
      :ok -> :ok
      {:error, [{message, _path} | _]} -> {:error, message, "#/#{name}"}
    end
  end

  defp type_mismatch(name, type) do
    {:error, "Type mismatch. Expected #{type} but got something else.", "#/#{name}"}
  end
end
