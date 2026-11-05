defmodule Mix.Tasks.Phx.Swagger.Generate do
  use Mix.Task
  require Logger

  @recursive true

  @shortdoc "Generates an OpenAPI 3.2 JSON file based on phoenix router"

  @moduledoc """
  Generates an OpenAPI 3.2 JSON file based on phoenix router and controllers.

  Usage:

      mix phx.swagger.generate

  Swagger file configuration must be defined in the project config, eg:

      config :your_app, :phoenix_swagger,
        swagger_files: %{
          "priv/static/swagger.json" => [router: YourAppWeb.Router, endpoint: YourAppWeb.Endpoint]
          # ... additional swagger files can be added here
        }
  """

  @default_title "<enter your title>"
  @default_version "0.0.1"
  @openapi_version "3.2.0"
  @component_key_pattern ~r/^[a-zA-Z0-9\.\-_]+$/

  @swagger2_replacements %{
    "swagger" => ~s(remove it, phoenix_swagger sets "openapi"),
    "host" => ~s(servers: [%{url: "https://host/base_path"}]),
    "basePath" => ~s(servers: [%{url: "/base_path"}]),
    "schemes" => ~s(servers: [%{url: "https://host"}]),
    "consumes" => "consumes/2 in each swagger_path",
    "produces" => "produces/2 in each swagger_path",
    "definitions" => "swagger_definitions/0 in controllers, or components: %{schemas: ...}",
    "securityDefinitions" => "components: %{securitySchemes: ...}",
    "parameters" => "components: %{parameters: ...}",
    "responses" => "components: %{responses: ...}"
  }

  defp app_name(), do: Mix.Project.get!().project()[:app]

  def run(_args) do
    Mix.Task.run("compile")
    Mix.Task.reenable("phx.swagger.generate")
    Code.append_path(Mix.Project.compile_path())

    swagger_files = swagger_files()

    if Enum.empty?(swagger_files) && !Mix.Task.recursing?() do
      Logger.warning("""
      No swagger configuration found. Ensure phoenix_swagger is configured, eg:

      config #{inspect(app_name())}, :phoenix_swagger,
        swagger_files: %{
          ...
        }
      """)
    end

    Enum.each(swagger_files, fn {output_file, config} ->
      result =
        with {:ok, router} <- attempt_load(config[:router]),
             {:ok, endpoint} <- attempt_load(config[:endpoint]) do
          write_file(output_file, swagger_document(router, endpoint))
        end

      case result do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Failed to generate #{output_file}: #{reason}")
      end
    end)
  end

  @doc false
  def swagger_files do
    app_name()
    |> Application.get_env(:phoenix_swagger, [])
    |> Keyword.get(:swagger_files, %{})
  end

  defp write_file(output_file, contents) do
    directory = Path.dirname(output_file)

    unless File.exists?(directory) do
      File.mkdir_p!(directory)
    end

    case File.read(output_file) do
      # Touch the file so `compile.phoenix_swagger` sees it as fresh.
      {:ok, ^contents} ->
        File.touch!(output_file)

      _ ->
        File.write!(output_file, contents)
        Logger.info("#{app_name()}: generated #{output_file}")
    end
  end

  defp attempt_load(nil), do: {:ok, nil}

  defp attempt_load(module_name) do
    case Code.ensure_compiled(module_name) do
      {:module, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to load module: #{module_name}: #{reason}"}
    end
  end

  defp swagger_document(router, endpoint) do
    routes = router.__routes__()
    controllers = load_controllers(routes)

    router
    |> collect_info()
    |> collect_servers(endpoint)
    |> collect_paths(routes, controllers)
    |> collect_schemas(controllers)
    |> sort_paths_and_schemas()
    |> PhoenixSwagger.json_library().encode!(pretty: true)
  end

  defp sort_paths_and_schemas(document) do
    document
    |> Map.update!(:paths, &PhoenixSwagger.OrderedObject.by_tag/1)
    |> update_in([:components, :schemas], &PhoenixSwagger.OrderedObject.new/1)
  end

  defp collect_info(router) do
    cond do
      function_exported?(router, :swagger_info, 0) ->
        Map.merge(default_swagger_info(), reject_swagger2_keys!(router.swagger_info()))

      function_exported?(Mix.Project.get(), :swagger_info, 0) ->
        info =
          Mix.Project.get().swagger_info()
          |> Keyword.put_new(:title, @default_title)
          |> Keyword.put_new(:version, @default_version)
          |> Enum.into(%{})

        %{default_swagger_info() | info: info}

      true ->
        default_swagger_info()
    end
  end

  def default_swagger_info do
    %{
      openapi: @openapi_version,
      info: %{
        title: @default_title,
        version: @default_version
      },
      paths: %{},
      components: %{schemas: %{}}
    }
  end

  defp reject_swagger2_keys!(info) do
    Enum.each(info, fn {key, _value} ->
      case @swagger2_replacements[to_string(key)] do
        nil ->
          :ok

        replacement ->
          raise ArgumentError,
                "swagger_info/0 returns the Swagger 2.0 key #{key}. " <>
                  "Use the OpenAPI 3.2 form instead: #{replacement}"
      end
    end)

    info
  end

  # Many routes share a controller, so load each one once.
  defp load_controllers(routes) do
    routes
    |> Enum.map(&find_controller/1)
    |> Enum.uniq()
    |> Enum.filter(fn controller ->
      case Code.ensure_compiled(controller) do
        {:module, _} ->
          true

        _ ->
          Logger.warning("Warning: #{controller} module didn't load.")
          false
      end
    end)
  end

  defp collect_paths(swagger_map, routes, controllers) do
    routes
    |> Enum.map(&find_swagger_path_function/1)
    |> Enum.filter(&(&1 && &1.controller in controllers))
    |> Enum.filter(&controller_function_exported?/1)
    |> Enum.map(&get_swagger_path/1)
    |> Enum.reduce(swagger_map, &merge_paths/2)
  end

  defp find_swagger_path_function(route = %{opts: action, path: path, verb: verb})
       when is_atom(action) do
    generate_swagger_path_function(route, action, path, verb)
  end

  # In Phoenix >= 1.4.7 the `opts` key was renamed to `plug_opts`
  defp find_swagger_path_function(route = %{plug_opts: action, path: path, verb: verb})
       when is_atom(action) do
    generate_swagger_path_function(route, action, path, verb)
  end

  defp find_swagger_path_function(_route) do
    # action not an atom usually means route to a plug which isn't a Phoenix controller
    nil
  end

  defp generate_swagger_path_function(route, action, path, verb) do
    %{
      controller: find_controller(route),
      swagger_fun: String.to_atom("swagger_path_#{action}"),
      path: format_path(path),
      verb: verb
    }
  end

  defp format_path(path) do
    Regex.replace(~r/:([^\/]+)/, path, "{\\1}")
  end

  defp controller_function_exported?(%{controller: controller, swagger_fun: fun}) do
    function_exported?(controller, fun, 1)
  end

  defp get_swagger_path(route = %{controller: controller, swagger_fun: fun}) do
    apply(controller, fun, [route])
  end

  defp merge_paths(path, swagger_map) do
    paths = Map.merge(swagger_map.paths, path, &merge_conflicts/3)
    %{swagger_map | paths: paths}
  end

  defp merge_conflicts(_key, value1, value2) do
    Map.merge(value1, value2)
  end

  defp collect_servers(document, nil), do: document

  defp collect_servers(document, endpoint) do
    endpoint_config = Application.get_env(app_name(), endpoint, [])

    case Keyword.get(endpoint_config, :url) do
      nil -> document
      _ -> collect_servers_from_endpoint(document, endpoint_config)
    end
  end

  defp collect_servers_from_endpoint(document, endpoint_config) do
    load_from_system_env = Keyword.get(endpoint_config, :load_from_system_env, false)
    url = Keyword.get(endpoint_config, :url)
    host = Keyword.get(url, :host, "localhost")
    port = Keyword.get(url, :port, 4000)

    if !load_from_system_env and is_binary(host) and (is_integer(port) or is_binary(port)) do
      servers = build_server_objects(url[:scheme], endpoint_config[:https], "#{host}:#{port}")
      Map.put_new(document, :servers, servers)
    else
      # host / port may be {:system, "ENV_VAR"} tuples or loaded in Endpoint.init callback
      document
    end
  end

  defp build_server_objects(scheme, _https, authority) when is_binary(scheme),
    do: [%{url: "#{scheme}://#{authority}"}]

  defp build_server_objects(nil, nil, authority) do
    # Scheme-relative, so clients keep the scheme the document was served with.
    [%{url: "//#{authority}"}]
  end

  defp build_server_objects(nil, _https, authority),
    do: [%{url: "https://#{authority}"}, %{url: "http://#{authority}"}]

  defp collect_schemas(document, controllers) do
    schemas =
      controllers
      |> Enum.filter(&function_exported?(&1, :swagger_definitions, 0))
      |> Enum.map(&apply(&1, :swagger_definitions, []))
      |> Enum.reduce(%{}, &Map.merge(&2, &1))

    Enum.each(Map.keys(schemas), &validate_component_key!/1)

    Map.update(document, :components, %{schemas: schemas}, fn components ->
      Map.update(components, :schemas, schemas, &Map.merge(&1, schemas))
    end)
  end

  defp validate_component_key!(key) do
    unless Regex.match?(@component_key_pattern, to_string(key)) do
      raise ArgumentError,
            "components.schemas key #{inspect(to_string(key))} must match " <>
              Regex.source(@component_key_pattern)
    end
  end

  defp find_controller(route_map) do
    Module.concat([:"Elixir" | Module.split(route_map.plug)])
  end
end
