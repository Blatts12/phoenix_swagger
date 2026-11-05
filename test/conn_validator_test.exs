defmodule PhoenixSwagger.ConnValidatorTest do
  use ExUnit.Case
  import Plug.Test

  alias PhoenixSwagger.{ConnValidator, Validator}

  setup do
    on_exit(&Validator.clear/0)
  end

  describe "servers base path" do
    test "matches requests when there are no servers" do
      parse_spec!(%{"paths" => %{"/pets" => %{"get" => %{}}}})

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/pets"))
    end

    test "matches requests when the server url has a trailing slash" do
      parse_spec!(%{
        "servers" => [%{"url" => "/api/"}],
        "paths" => %{"/pets/" => %{"get" => %{}}}
      })

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/api/pets"))
    end

    test "uses the path of an absolute server url" do
      parse_spec!(%{
        "servers" => [%{"url" => "https://api.example.com/v1"}],
        "paths" => %{"/pets" => %{"get" => %{}}}
      })

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/v1/pets"))
      assert {:error, :no_matching_path} = ConnValidator.validate(build_conn(:get, "/pets"))
    end

    test "substitutes server variable defaults" do
      parse_spec!(%{
        "servers" => [
          %{"url" => "/api/{version}", "variables" => %{"version" => %{"default" => "v2"}}}
        ],
        "paths" => %{"/pets" => %{"get" => %{}}}
      })

      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/api/v2/pets"))
    end
  end

  describe "JSON request bodies" do
    test "accept an inline schema without $ref" do
      parse_spec!(%{
        "paths" => %{
          "/pets" => %{
            "post" => %{
              "requestBody" => %{
                "content" => %{
                  "application/json" => %{
                    "schema" => %{
                      "type" => "object",
                      "required" => ["name"],
                      "properties" => %{"name" => %{"type" => "string"}}
                    }
                  }
                }
              }
            }
          }
        }
      })

      assert {:ok, _} = ConnValidator.validate(build_conn(:post, "/pets", %{"name" => "Rex"}))

      assert {:error, message, "#"} = ConnValidator.validate(build_conn(:post, "/pets", %{}))
      assert message =~ ~r/'name' is required/
    end
  end

  describe "multipart form bodies" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/uploads" => %{
            "post" => %{
              "requestBody" => %{
                "content" => %{
                  "multipart/form-data" => %{
                    "schema" => %{
                      "type" => "object",
                      "required" => ["document"],
                      "properties" => %{
                        "document" => %{"contentMediaType" => "application/octet-stream"},
                        "age" => %{"type" => "integer"},
                        "public" => %{"type" => "boolean"}
                      }
                    }
                  }
                }
              }
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

  describe "urlencoded form bodies" do
    setup do
      parse_spec!(%{
        "paths" => %{
          "/people" => %{
            "post" => %{
              "requestBody" => %{
                "content" => %{
                  "application/x-www-form-urlencoded" => %{
                    "schema" => %{
                      "type" => "object",
                      "properties" => %{"age" => %{"type" => "integer", "minimum" => 0}}
                    }
                  }
                }
              }
            }
          }
        }
      })
    end

    test "parse an integer field before checking it" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:post, "/people", %{"age" => "42"}))
    end

    test "reject an integer field that does not parse" do
      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/age"} =
               ConnValidator.validate(build_conn(:post, "/people", %{"age" => "old"}))
    end

    test "check constraints on the parsed value" do
      assert {:error, message, "#/age"} =
               ConnValidator.validate(build_conn(:post, "/people", %{"age" => "-1"}))

      assert message =~ ~r/0/
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
                  "schema" => %{"type" => "integer"},
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
                  "style" => "form",
                  "explode" => false,
                  "schema" => %{"type" => "array", "items" => %{"type" => "string"}}
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
                  "schema" => %{"type" => "integer", "minimum" => 1, "maximum" => 50}
                },
                %{
                  "name" => "code",
                  "in" => "query",
                  "schema" => %{"type" => "string", "pattern" => "^[A-Z]{3}$"}
                },
                %{
                  "name" => "level",
                  "in" => "query",
                  "schema" => %{"type" => "integer", "enum" => [1, 2]}
                },
                %{
                  "name" => "since",
                  "in" => "query",
                  "schema" => %{"type" => "integer", "format" => "int64"}
                }
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
      assert {:error, message, "#/limit"} = Validator.validate("/get/pets", %{"limit" => 51})
      assert message =~ ~r/50/
    end

    test "reject a value above maximum" do
      assert {:error, message, "#/limit"} =
               ConnValidator.validate(build_conn(:get, "/pets?limit=51"))

      assert message =~ ~r/50/
    end

    test "reject a value that misses the pattern" do
      assert {:error, message, "#/code"} =
               ConnValidator.validate(build_conn(:get, "/pets?code=abc"))

      assert message =~ ~r/pattern/
    end

    test "compare integer enums against the parsed value" do
      assert {:error, "Value 3 is not allowed in enum.", "#/level"} =
               ConnValidator.validate(build_conn(:get, "/pets?level=3"))
    end
  end

  describe "OpenAPI parameter serialization" do
    setup do
      Validator.parse_swagger_schema("test/test_spec/openapi_styles_spec.json")
      :ok
    end

    test "form without explode splits on commas" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/csv?tags=a,b"))
    end

    test "pipeDelimited splits on pipes" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/pipes?tags=a|b"))

      assert {:error, ~s(Value "a,b" is not allowed in enum.), "#/tags"} =
               ConnValidator.validate(build_conn(:get, "/pipes?tags=a,b"))
    end

    test "spaceDelimited splits on spaces" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/spaces?tags=a%20b"))
    end

    test "default form explode reads every repeated key" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/exploded?ids=1&ids=2"))

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/ids"} =
               ConnValidator.validate(build_conn(:get, "/exploded?ids=1&ids=x"))

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/ids"} =
               ConnValidator.validate(build_conn(:get, "/exploded?ids=x&ids=1"))
    end

    test "path item parameters apply to every operation" do
      assert {:ok, _} = ConnValidator.validate(build_path_conn(:get, "/shared/1", "1"))

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/id"} =
               ConnValidator.validate(build_path_conn(:get, "/shared/abc", "abc"))

      assert {:error, "Type mismatch. Expected Boolean but got something else.", "#/verbose"} =
               ConnValidator.validate(build_path_conn(:get, "/shared/1?verbose=maybe", "1"))
    end

    test "operation parameters replace path item parameters with the same name and location" do
      assert {:ok, _} =
               ConnValidator.validate(build_path_conn(:put, "/shared/1?verbose=yes", "1"))

      assert {:error, ~s(Value "true" is not allowed in enum.), "#/verbose"} =
               ConnValidator.validate(build_path_conn(:put, "/shared/1?verbose=true", "1"))
    end

    test "Authorization header and cookie parameters are not enforced" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/secured"))
    end

    test "querystring parameters are not enforced" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:get, "/raw"))
    end

    test "QUERY and TRACE operations match their methods" do
      assert {:ok, _} = ConnValidator.validate(build_conn(:query, "/search?limit=5"))

      assert {:error, "Type mismatch. Expected Integer but got something else.", "#/limit"} =
               ConnValidator.validate(build_conn(:query, "/search?limit=five"))

      assert {:ok, _} = ConnValidator.validate(build_conn(:trace, "/search"))
    end
  end

  defp build_path_conn(method, path, id) do
    conn = build_conn(method, path)
    %{conn | path_params: %{"id" => id}, params: Map.put(conn.params, "id", id)}
  end

  defp parse_spec!(spec) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_conn_#{System.unique_integer([:positive])}.json"
      )

    spec =
      Map.merge(
        %{"openapi" => "3.2.0", "info" => %{"title" => "Test", "version" => "1.0.0"}},
        spec
      )

    File.write!(path, Jason.encode!(spec))
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
