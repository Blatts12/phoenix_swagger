defmodule PhoenixSwagger.OrderedObject do
  @moduledoc false

  # JSON object that encodes entries in a chosen order.
  # Elixir maps only keep a deterministic key order up to 32 entries, and atom
  # keys are ordered by creation rather than name, so the generated document
  # wraps `paths` and `definitions` in this struct.

  # Swagger path items store tags on each operation. `get` is the primary
  # operation when several methods on one path declare different tags.
  @http_methods ~w(get put post delete options head patch)

  defstruct pairs: []

  @doc false
  def new(map) when is_map(map) do
    map
    |> pairs()
    |> Enum.sort_by(&elem(&1, 0))
    |> wrap()
  end

  @doc false
  def by_tag(map) when is_map(map) do
    map
    |> pairs()
    |> Enum.sort_by(fn {path, path_item} -> {primary_tag(path_item), path} end)
    |> wrap()
  end

  defp pairs(map) do
    Enum.map(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp wrap(pairs), do: %__MODULE__{pairs: pairs}

  defp primary_tag(path_item) when is_map(path_item) do
    Enum.find_value(@http_methods, "", fn method ->
      case path_item[method] do
        %{"tags" => [tag | _]} -> to_string(tag)
        _ -> nil
      end
    end)
  end

  defp primary_tag(_path_item), do: ""
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: PhoenixSwagger.OrderedObject do
    def encode(%{pairs: pairs}, opts) do
      Jason.Encode.keyword(pairs, opts)
    end
  end
end
