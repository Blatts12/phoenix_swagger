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

  defmodule ConfiguredEndpoint do
  end

  defmodule EmptyRouter do
    def __routes__, do: []
  end

  defmodule InfoRouter do
    def __routes__, do: []
    def swagger_info, do: Application.fetch_env!(:phoenix_swagger, :test_swagger_info)
  end

  defmodule BadNameController do
    def swagger_definitions, do: %{"User Resource": %{"type" => "object"}}
  end

  defmodule BadNameRouter do
    def __routes__, do: [%{plug: BadNameController, plug_opts: :index, path: "/", verb: :get}]
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

  test "writes paths grouped by tag and schemas in alphabetical order", %{output: output} do
    Mix.Task.run("phx.swagger.generate")

    json = File.read!(output)
    paths = Regex.scan(~r{"/p\d+"}, json) |> Enum.map(&hd/1)

    assert paths == tagged_paths("A") ++ tagged_paths("B")
    assert %{"components" => %{"schemas" => %{"Apple" => _}}} = Jason.decode!(json)
    assert_before(json, "\"Apple\"", "\"Mango\"")
    assert_before(json, "\"Mango\"", "\"Zebra\"")
  end

  test "writes the file when the endpoint has no application config", %{output: output} do
    document = generate!(output, router: Router, endpoint: UnconfiguredEndpoint)
    refute Map.has_key?(document, "servers")
  end

  test "writes a default OpenAPI 3.2 document", %{output: output} do
    assert generate!(output, router: EmptyRouter) == %{
             "openapi" => "3.2.0",
             "info" => %{"title" => "<enter your title>", "version" => "0.0.1"},
             "paths" => %{},
             "components" => %{"schemas" => %{}}
           }
  end

  describe "servers from the endpoint" do
    setup do
      on_exit(fn -> Application.delete_env(:phoenix_swagger, ConfiguredEndpoint) end)
    end

    test "scheme-relative url without https config", %{output: output} do
      put_endpoint_config(url: [host: "localhost", port: 4000])

      assert generate!(output, router: EmptyRouter, endpoint: ConfiguredEndpoint)["servers"] ==
               [%{"url" => "//localhost:4000"}]
    end

    test "url scheme from the endpoint config", %{output: output} do
      put_endpoint_config(url: [scheme: "https", host: "api.example.com", port: 443])

      assert generate!(output, router: EmptyRouter, endpoint: ConfiguredEndpoint)["servers"] ==
               [%{"url" => "https://api.example.com:443"}]
    end

    test "https and http with https config", %{output: output} do
      put_endpoint_config(url: [host: "localhost", port: 4000], https: [port: 4001])

      assert generate!(output, router: EmptyRouter, endpoint: ConfiguredEndpoint)["servers"] == [
               %{"url" => "https://localhost:4000"},
               %{"url" => "http://localhost:4000"}
             ]
    end

    test "servers from swagger_info win", %{output: output} do
      put_endpoint_config(url: [host: "localhost", port: 4000])
      put_swagger_info(%{servers: [%{url: "/api"}]})

      assert generate!(output, router: InfoRouter, endpoint: ConfiguredEndpoint)["servers"] ==
               [%{"url" => "/api"}]
    end
  end

  test "components from swagger_info sit beside collected schemas", %{output: output} do
    put_swagger_info(%{
      components: %{securitySchemes: %{bearer: %{type: "http", scheme: "bearer"}}}
    })

    assert generate!(output, router: InfoRouter)["components"] == %{
             "schemas" => %{},
             "securitySchemes" => %{"bearer" => %{"type" => "http", "scheme" => "bearer"}}
           }
  end

  for {key, replacement} <- [
        basePath: "servers",
        host: "servers",
        schemes: "servers",
        swagger: "openapi",
        consumes: "consumes",
        produces: "produces",
        definitions: "swagger_definitions",
        securityDefinitions: "securitySchemes",
        parameters: "components",
        responses: "components"
      ] do
    test "swagger_info with Swagger 2.0 key #{key} raises", %{output: output} do
      put_swagger_info(%{unquote(key) => "legacy"})

      assert_raise ArgumentError, ~r/#{unquote(key)}.*#{unquote(replacement)}/s, fn ->
        generate!(output, router: InfoRouter)
      end
    end
  end

  test "schema names outside the component key pattern raise", %{output: output} do
    assert_raise ArgumentError, ~r/\^\[a-zA-Z0-9/, fn ->
      generate!(output, router: BadNameRouter)
    end
  end

  test "sample API generates a valid OpenAPI 3.2 document", %{output: output} do
    document = generate!(output, router: PhoenixSwagger.SampleApi.Router)
    assert :ok = PhoenixSwagger.OpenApiConformance.assert_valid_openapi_document(document)
  end

  defp generate!(output, config) do
    Application.put_env(:phoenix_swagger, :phoenix_swagger, swagger_files: %{output => config})
    Mix.Task.run("phx.swagger.generate")
    output |> File.read!() |> Jason.decode!()
  end

  defp put_endpoint_config(config) do
    Application.put_env(:phoenix_swagger, ConfiguredEndpoint, config)
  end

  defp put_swagger_info(info) do
    Application.put_env(:phoenix_swagger, :test_swagger_info, info)
    on_exit(fn -> Application.delete_env(:phoenix_swagger, :test_swagger_info) end)
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
