defmodule PhoenixSwagger.OpenApiConformance do
  @moduledoc false

  # Validates documents against the official OpenAPI 3.2 schema, vendored from
  # https://spec.openapis.org/oas/3.2/schema/2025-09-17

  @schema_file Path.expand("fixtures/oas-3.2-schema-2025-09-17.json", __DIR__)
  @external_resource @schema_file

  def assert_valid_openapi_document(document) when is_map(document) do
    case JSV.validate(document, fetch_openapi_schema_root()) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        ExUnit.Assertions.flunk(
          "Document is not a valid OpenAPI 3.2 document:\n" <>
            inspect(JSV.normalize_error(error), pretty: true, limit: :infinity)
        )
    end
  end

  defp fetch_openapi_schema_root do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        root = @schema_file |> File.read!() |> Jason.decode!() |> JSV.build!()
        :persistent_term.put(__MODULE__, root)
        root

      root ->
        root
    end
  end
end
