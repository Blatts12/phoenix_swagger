defmodule Mix.Tasks.Compile.PhoenixSwagger do
  use Mix.Task.Compiler

  alias Mix.Tasks.Phx.Swagger.Generate

  @shortdoc "Compiles swagger annotations to JSON file"

  @moduledoc """
  Regenerates swagger files when one is missing or older than the newest
  compiled module or config file. Pass `--force` to always regenerate.

  See documentation for `Mix.Tasks.Phx.Swagger.Generate`
  """

  def run(args) do
    if "--force" in args or swagger_files_stale?() do
      Mix.Task.run("phx.swagger.generate")
      {:ok, []}
    else
      {:noop, []}
    end
  end

  defp swagger_files_stale? do
    case Map.keys(Generate.swagger_files()) do
      [] ->
        true

      outputs ->
        build_mtime = newest_build_mtime()
        Enum.any?(outputs, &(posix_mtime(&1) < build_mtime))
    end
  end

  defp newest_build_mtime do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.reduce(Mix.Project.config_mtime(), &max(posix_mtime(&1), &2))
  end

  defp posix_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> 0
    end
  end
end
