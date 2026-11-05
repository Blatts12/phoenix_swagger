defmodule PhoenixSwagger.Mixfile do
  use Mix.Project

  @source_url "https://github.com/Blatts12/phoenix_swagger"
  @version "0.9.0"

  def project do
    [
      app: :phoenix_swagger,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      xref: [
        exclude: [
          JSV,
          JSV.Ref
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env()) ++ [:logger, :eex]
    ]
  end

  defp extra_applications(:test) do
    [:jason, :jsv]
  end

  defp extra_applications(_), do: []

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4", optional: true},
      {:jsv, "~> 0.27", optional: true},
      {:plug, "~> 1.14"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: :dev},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description:
        "PhoenixSwagger is the library that provides OpenAPI 3.2 " <>
          "integration to the phoenix web framework.",
      maintainers: ["Alexander Kuleshov", "Jakub Melkowski"],
      licenses: ["MPL-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/phoenix_swagger/changelog.html",
        "GitHub" => @source_url,
        "Slack" => "https://elixir-lang.slack.com/messages/phoenix_swagger"
      },
      files: ~w(lib mix.exs .formatter.exs README.md CHANGELOG.md LICENSE priv)
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md",
        {:LICENSE, [title: "License"]},
        {:"README.md", [title: "Overview"]},
        "guides/getting-started.md",
        "guides/schemas.md",
        "guides/operations.md",
        "guides/reusing-swagger-parameters.md",
        "guides/swagger-ui.md",
        "guides/schema-validation.md",
        "guides/test-helpers.md",
        "guides/live-reloading.md",
        "guides/json-api-helpers.md"
      ],
      groups_for_extras: [Guides: ~r/guides\/[^\/]+\.md/],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @source_url,
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
