defmodule Mix.Tasks.Compile.PhoenixSwaggerTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.PhoenixSwagger, as: Compiler

  defmodule PingController do
    def swagger_path_ping(_route), do: %{"/ping" => %{"get" => %{"tags" => ["Ping"]}}}
  end

  defmodule Router do
    def __routes__, do: [%{plug: PingController, plug_opts: :ping, path: "/ping", verb: :get}]
  end

  setup do
    output =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_compile_#{System.unique_integer([:positive])}.json"
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

  test "generates missing swagger files", %{output: output} do
    assert {:ok, []} = Compiler.run([])
    assert File.exists?(output)
  end

  test "skips generation when swagger files are newer than the build", %{output: output} do
    assert {:ok, []} = Compiler.run([])
    File.write!(output, "untouched")

    assert {:noop, []} = Compiler.run([])
    assert File.read!(output) == "untouched"
  end

  test "regenerates with --force", %{output: output} do
    assert {:ok, []} = Compiler.run([])
    File.write!(output, "stale")

    assert {:ok, []} = Compiler.run(["--force"])
    assert output |> File.read!() |> Jason.decode!() |> Map.has_key?("paths")
  end
end
