defmodule PhoenixSwagger.OrderedObject do
  @moduledoc false

  # JSON object that encodes entries in alphabetical key order.
  # Elixir maps only keep a deterministic key order up to 32 entries, and atom
  # keys are ordered by creation rather than name, so the generated document
  # wraps `paths` and `definitions` in this struct.

  defstruct pairs: []

  @doc false
  def new(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))

    %__MODULE__{pairs: pairs}
  end
end

if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: PhoenixSwagger.OrderedObject do
    def encode(%{pairs: pairs}, opts) do
      Jason.Encode.keyword(pairs, opts)
    end
  end
end

if Code.ensure_loaded?(Poison.Encoder) do
  defimpl Poison.Encoder, for: PhoenixSwagger.OrderedObject do
    alias Poison.Encoder

    use Poison.Encode
    use Poison.Pretty

    def encode(%{pairs: []}, _options), do: "{}"

    def encode(%{pairs: pairs}, options) do
      encode_pairs(pairs, pretty(options), options)
    end

    defp encode_pairs(pairs, true, options) do
      indent = indent(options)
      offset = offset(options) + indent
      options = offset(options, offset)
      separator = [",\n", spaces(offset)]

      [
        "{\n",
        spaces(offset),
        Enum.map_intersperse(pairs, separator, &encode_pair(&1, ": ", options)),
        ?\n,
        spaces(offset - indent),
        ?}
      ]
    end

    defp encode_pairs(pairs, _pretty, options) do
      [
        ?{,
        Enum.map_intersperse(pairs, ?,, &encode_pair(&1, ":", options)),
        ?}
      ]
    end

    defp encode_pair({key, value}, separator, options) do
      [
        Encoder.BitString.encode(encode_name(key), options),
        separator,
        Encoder.encode(value, options)
      ]
    end
  end
end
