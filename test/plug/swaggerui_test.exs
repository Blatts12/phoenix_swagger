defmodule PhoenixSwagger.Plug.SwaggerUITest do
  use ExUnit.Case
  use Plug.Test

  alias PhoenixSwagger.Plug.SwaggerUI

  test "init/1 renders config_url and config_object into the SwaggerUI bundle" do
    opts =
      SwaggerUI.init(
        otp_app: :phoenix_swagger,
        swagger_file: "swagger.json",
        config_url: "/cfg",
        config_object: %{"docExpansion" => "none", a: 1}
      )

    assert opts[:body] =~ ~s(configUrl: "/cfg")
    assert opts[:body] =~ ~s(docExpansion: "none")
    assert opts[:body] =~ "a: 1"
  end

  test "init/1 omits optional config when it is not provided" do
    opts = SwaggerUI.init(otp_app: :phoenix_swagger, swagger_file: "swagger.json")

    refute opts[:body] =~ "configUrl"
    refute opts[:body] =~ "docExpansion"
  end

  test "404 JSON response honors a negotiated application/json Accept header" do
    opts = SwaggerUI.init(otp_app: :phoenix_swagger, swagger_file: "swagger.json")

    conn =
      :get
      |> conn("/missing.json")
      |> put_req_header("accept", "application/json, text/plain")
      |> SwaggerUI.call(opts)

    assert {404, headers, body} = sent_resp(conn)
    assert get_header(headers, "content-type") =~ "application/json"
    assert Jason.decode!(body) == %{"Error" => "not found"}
  end

  defp get_header(headers, name) do
    {^name, value} = List.keyfind(headers, name, 0)
    value
  end
end
