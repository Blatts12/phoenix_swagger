defmodule Mix.Tasks.Phx.Swagger.GenerateTest do
  use ExUnit.Case, async: false

  defmodule BulkController do
    for i <- 1..33 do
      padded = String.pad_leading(Integer.to_string(i), 2, "0")
      path = "/p" <> padded

      tag = if rem(i, 2) == 0, do: "A", else: "B"

      def unquote(:"swagger_path_item_#{padded}")(_route) do
        %{
          unquote(path) => %{
            "get" => %{"operationId" => unquote(padded), "tags" => [unquote(tag)]}
          }
        }
      end
    end

    def swagger_definitions do
      %{
        Zebra: %{"type" => "object"},
        Apple: %{"type" => "object"},
        Mango: %{"type" => "object"}
      }
    end
  end

  defmodule Router do
    def __routes__ do
      for i <- 33..1//-1 do
        padded = String.pad_leading(Integer.to_string(i), 2, "0")

        %{
          plug: BulkController,
          plug_opts: :"item_#{padded}",
          path: "/p#{padded}",
          verb: :get
        }
      end
    end
  end

  defmodule UnconfiguredEndpoint do
  end

  setup do
    output =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_generate_#{System.unique_integer([:positive])}.json"
      )

    previous = Application.get_env(:phoenix_swagger, :phoenix_swagger)

    Application.put_env(:phoenix_swagger, :phoenix_swagger,
      swagger_files: %{output => [router: Router]}
    )

    on_exit(fn ->
      File.rm(output)

      if previous do
        Application.put_env(:phoenix_swagger, :phoenix_swagger, previous)
      else
        Application.delete_env(:phoenix_swagger, :phoenix_swagger)
      end
    end)

    %{output: output}
  end

  test "writes paths grouped by tag and definitions in alphabetical order", %{output: output} do
    Mix.Task.run("phx.swagger.generate")

    json = File.read!(output)
    paths = Regex.scan(~r{"/p\d+"}, json) |> Enum.map(&hd/1)

    assert paths == tagged_paths("A") ++ tagged_paths("B")
    assert_before(json, "\"Apple\"", "\"Mango\"")
    assert_before(json, "\"Mango\"", "\"Zebra\"")
  end

  test "writes the file when the endpoint has no application config", %{output: output} do
    Application.put_env(:phoenix_swagger, :phoenix_swagger,
      swagger_files: %{output => [router: Router, endpoint: UnconfiguredEndpoint]}
    )

    Mix.Task.run("phx.swagger.generate")

    refute output |> File.read!() |> Jason.decode!() |> Map.has_key?("host")
  end

  test "logs that swagger files are up to date when nothing changed" do
    first_run = ExUnit.CaptureLog.capture_log(fn -> Mix.Task.run("phx.swagger.generate") end)
    refute first_run =~ "up to date"

    second_run = ExUnit.CaptureLog.capture_log(fn -> Mix.Task.run("phx.swagger.generate") end)
    assert second_run =~ "phoenix_swagger: swagger files are up to date, nothing to generate"
    refute second_run =~ "generated"
  end

  defp tagged_paths(tag) do
    remainder = if tag == "A", do: 0, else: 1

    for i <- 1..33, rem(i, 2) == remainder do
      ~s("/p#{String.pad_leading(Integer.to_string(i), 2, "0")}")
    end
  end

  defp assert_before(json, earlier, later) do
    {earlier_at, _} = :binary.match(json, earlier)
    {later_at, _} = :binary.match(json, later)
    assert earlier_at < later_at
  end
end
