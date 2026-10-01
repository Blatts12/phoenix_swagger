defmodule PhoenixSwagger.OrderedObjectTest do
  use ExUnit.Case, async: true

  alias PhoenixSwagger.OrderedObject

  test "sorts keys alphabetically past the small-map limit" do
    object =
      for i <- 40..1//-1, into: %{} do
        {"key" <> String.pad_leading(Integer.to_string(i), 2, "0"), i}
      end
      |> OrderedObject.new()

    for pretty <- [false, true] do
      json = Jason.encode!(object, pretty: pretty)
      keys = Regex.scan(~r/"key\d+"/, json) |> Enum.map(&hd/1)

      assert keys == Enum.sort(keys), "pretty=#{pretty} did not sort keys: #{inspect(keys)}"
    end
  end

  test "sorts atom keys by name" do
    json = Jason.encode!(OrderedObject.new(%{Zebra: 1, Apple: 2, Mango: 3}))

    assert json == ~s({"Apple":2,"Mango":3,"Zebra":1})
  end

  test "encodes an empty object" do
    assert Jason.encode!(OrderedObject.new(%{})) == "{}"
  end

  test "sorts paths by tag, then by path" do
    paths = %{
      "/z" => %{"get" => %{"tags" => ["B"]}},
      "/a" => %{"get" => %{"tags" => ["B"]}},
      "/m" => %{"post" => %{"tags" => ["A"]}},
      "/untagged" => %{"get" => %{}}
    }

    assert Jason.encode!(OrderedObject.by_tag(paths)) ==
             ~s({"/untagged":{"get":{}},"/m":{"post":{"tags":["A"]}},"/a":{"get":{"tags":["B"]}},"/z":{"get":{"tags":["B"]}}})
  end

  test "uses the get operation's tag when methods disagree" do
    paths = %{
      "/item" => %{"get" => %{"tags" => ["M"]}, "post" => %{"tags" => ["Z"]}},
      "/middle" => %{"get" => %{"tags" => ["P"]}}
    }

    json = Jason.encode!(OrderedObject.by_tag(paths))
    assert json =~ ~s("/item":)
    {item, _} = :binary.match(json, "\"/item\"")
    {middle, _} = :binary.match(json, "\"/middle\"")
    assert item < middle
  end
end
