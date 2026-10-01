defmodule PhoenixSwagger.ConnValidatorTest do
  use ExUnit.Case
  import Plug.Test

  alias PhoenixSwagger.{ConnValidator, Validator}

  setup do
    on_exit(&Validator.clear/0)
  end

  describe "basePath" do
    test "matches requests when basePath is the root" do
      parse_spec!(%{"basePath" => "/", "paths" => %{"/pets" => %{"get" => %{}}}})

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/pets"))
    end

    test "matches requests when basePath has a trailing slash" do
      parse_spec!(%{"basePath" => "/api/", "paths" => %{"/pets/" => %{"get" => %{}}}})

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/api/pets"))
    end
  end

  describe "body parameters" do
    test "accept an inline schema without $ref" do
      parse_spec!(%{
        "paths" => %{
          "/pets" => %{
            "post" => %{
              "parameters" => [
                %{
                  "name" => "pet",
                  "in" => "body",
                  "schema" => %{
                    "type" => "object",
                    "required" => ["name"],
                    "properties" => %{"name" => %{"type" => "string"}}
                  }
                }
              ]
            }
          }
        }
      })

      assert {:ok, _} = ConnValidator.validate(build_conn(:post, "/pets", %{"name" => "Rex"}))

      assert {:error, "Required property name was not present.", "#"} =
               ConnValidator.validate(build_conn(:post, "/pets", %{}))
    end
  end

  describe "formData parameters" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/uploads" => %{
            "post" => %{
              "parameters" => [
                %{"name" => "document", "in" => "formData", "type" => "file", "required" => true},
                %{"name" => "age", "in" => "formData", "type" => "integer"},
                %{"name" => "public", "in" => "formData", "type" => "boolean"}
              ]
            }
          }
        }
      })
    end

    test "parse typed values sent as form strings" do
      conn =
        build_conn(:post, "/uploads", %{"document" => upload(), "age" => "5", "public" => "true"})

      assert {:ok, _} = ConnValidator.validate(conn)
    end

    test "reject a form string that is not the declared type" do
      conn = build_conn(:post, "/uploads", %{"document" => upload(), "age" => "five"})

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/age"} =
               ConnValidator.validate(conn)
    end

    test "enforce required fields" do
      assert {:error, "Required property document was not present.", "#"} =
               ConnValidator.validate(build_conn(:post, "/uploads", %{"age" => "5"}))
    end
  end

  describe "header parameters" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/pets" => %{
            "get" => %{
              "parameters" => [
                %{
                  "name" => "X-Request-Id",
                  "in" => "header",
                  "type" => "integer",
                  "required" => true
                }
              ]
            }
          }
        }
      })
    end

    test "read the value from request headers" do
      conn = :get |> build_conn("/pets") |> Plug.Conn.put_req_header("x-request-id", "42")

      assert {:ok, _} = ConnValidator.validate(conn)
    end

    test "enforce required headers" do
      assert {:error, "Required property X-Request-Id was not present.", "#"} =
               ConnValidator.validate(build_conn(:get, "/pets"))
    end

    test "reject a header that is not the declared type" do
      conn = :get |> build_conn("/pets") |> Plug.Conn.put_req_header("x-request-id", "abc")

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/X-Request-Id"} =
               ConnValidator.validate(conn)
    end
  end

  describe "array query parameters" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/contents" => %{
            "get" => %{
              "parameters" => [
                %{
                  "name" => "uuids",
                  "in" => "query",
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "collectionFormat" => "csv"
                }
              ]
            }
          }
        }
      })
    end

    test "accept csv and bracket syntax" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/contents?uuids=a1,b2"))

      assert {:ok, _} =
               ConnValidator.validate(build_conn(:get, "/contents?uuids[]=a1&uuids[]=b2"))
    end

    test "reject a nested map instead of crashing" do
      assert {:error, "Type mismatch. Expected Array but got something else.", "#/uuids"} =
               ConnValidator.validate(build_conn(:get, "/contents?uuids[foo]=x"))
    end
  end

  describe "query parameter constraints" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/pets" => %{
            "get" => %{
              "parameters" => [
                %{
                  "name" => "limit",
                  "in" => "query",
                  "type" => "integer",
                  "minimum" => 1,
                  "maximum" => 50
                },
                %{
                  "name" => "code",
                  "in" => "query",
                  "type" => "string",
                  "pattern" => "^[A-Z]{3}$"
                },
                %{"name" => "level", "in" => "query", "type" => "integer", "enum" => [1, 2]},
                %{"name" => "since", "in" => "query", "type" => "integer", "format" => "int64"}
              ]
            }
          }
        }
      })
    end

    test "accept values inside the declared bounds" do
      assert {:ok, _} =
               ConnValidator.validate(build_conn(:get, "/pets?limit=10&code=ABC&level=2&since=7"))
    end

    test "apply to typed params passed to Validator.validate/2" do
      assert {:error, "Expected the value to be <= 50", "#/limit"} =
               Validator.validate("/get/pets", %{"limit" => 51})
    end

    test "reject a value above maximum" do
      assert {:error, "Expected the value to be <= 50", "#/limit"} =
               ConnValidator.validate(build_conn(:get, "/pets?limit=51"))
    end

    test "reject a value that misses the pattern" do
      assert {:error, ~s(Does not match pattern "^[A-Z]{3}$".), "#/code"} =
               ConnValidator.validate(build_conn(:get, "/pets?code=abc"))
    end

    test "compare integer enums against the parsed value" do
      assert {:error, "Value 3 is not allowed in enum.", "#/level"} =
               ConnValidator.validate(build_conn(:get, "/pets?level=3"))
    end
  end

  defp parse_spec!(spec) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_conn_#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Map.put(spec, "swagger", "2.0")))
    on_exit(fn -> File.rm(path) end)
    Validator.parse_swagger_schema(path)
  end

  defp build_conn(method, path, body_params \\ %{}) do
    conn = method |> conn(path) |> Plug.Conn.fetch_query_params()
    %{conn | body_params: body_params, params: Map.merge(conn.query_params, body_params)}
  end

  defp upload do
    %Plug.Upload{path: "/tmp/doc.pdf", filename: "doc.pdf", content_type: "application/pdf"}
  end
end
