defmodule PhoenixSwagger.OrderedObjectTest do
  use ExUnit.Case, async: true

  alias PhoenixSwagger.OrderedObject

  test "sorts keys alphabetically past the small-map limit" do
    object =
      for i <- 40..1//-1, into: %{} do
        {"key" <> String.pad_leading(Integer.to_string(i), 2, "0"), i}
      end
      |> OrderedObject.new()

    for encoder <- [Jason, Poison], pretty <- [false, true] do
      json = encoder.encode!(object, pretty: pretty)
      keys = Regex.scan(~r/"key\d+"/, json) |> Enum.map(&hd/1)

      assert keys == Enum.sort(keys),
             "#{inspect(encoder)} pretty=#{pretty} did not sort keys: #{inspect(keys)}"
    end
  end

  test "sorts atom keys by name" do
    json = Jason.encode!(OrderedObject.new(%{Zebra: 1, Apple: 2, Mango: 3}))

    assert json == ~s({"Apple":2,"Mango":3,"Zebra":1})
  end

  test "encodes an empty object" do
    assert Jason.encode!(OrderedObject.new(%{})) == "{}"
    assert Poison.encode!(OrderedObject.new(%{})) == "{}"
  end
end
