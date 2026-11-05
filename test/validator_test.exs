defmodule ValidatorTest do
  use ExUnit.Case

  alias PhoenixSwagger.Validator

  setup do
    schema =
      Validator.parse_swagger_schema([
        "test/test_spec/openapi_test_spec.json",
        "test/test_spec/openapi_test_spec_2.json"
      ])

    on_exit(&Validator.clear/0)

    {:ok, schema}
  end

  test "parse_swagger_schema() test", schemas do
    price = schemas["/get/estimates/price"].schema["properties"]
    time = schemas["/get/estimates/time"].schema["properties"]
    history = schemas["/get/history"].schema["properties"]
    products_post = schemas["/post/products"].schema["properties"]
    products_get = schemas["/get/products"].schema["properties"]

    assert %{
             "end_latitude" => %{"type" => "integer"},
             "end_longitude" => %{"type" => "integer"},
             "start_latitude" => %{"type" => "integer"},
             "start_longitude" => %{"type" => "integer"}
           } = price

    assert %{
             "customer_uuid" => %{"type" => "string"},
             "product_id" => %{"type" => "string"},
             "start_latitude" => %{"type" => "integer"},
             "start_longitude" => %{"type" => "integer"}
           } = time

    assert %{"limit" => %{"type" => "integer"}, "offset" => %{"type" => "integer"}} = history

    assert %{"latitude" => %{"type" => "integer"}, "longitude" => %{"type" => "integer"}} =
             products_get

    assert %{
             "latitude" => %{"type" => "integer"},
             "longitude" => %{"type" => "integer"},
             "ID" => %{"type" => "integer"}
           } = products_post

    pets_get = schemas["/get/pets"].schema["properties"]
    pets_post = schemas["/post/pets"].schema["properties"]
    pet_id = schemas["/get/pets/{id}"].schema["properties"]
    pet_delete = schemas["/delete/pets/{id}"].schema["properties"]

    assert %{"tags" => %{"type" => "array"}, "limit" => %{"type" => "integer"}} = pets_get

    assert %{
             "id" => %{"format" => "int64", "type" => "integer"},
             "pet" => %{"$ref" => "#/components/schemas/Pet"}
           } = pets_post

    assert %{"id" => %{"type" => "integer"}} = pet_id
    assert %{"id" => %{"type" => "integer"}} = pet_delete

    assert %{"type" => "object"} = schemas["/get/me"].schema
  end

  test "parse_swagger_schema/1 raises when the file is missing" do
    assert_raise File.Error, ~r/does_not_exist\.json/, fn ->
      Validator.parse_swagger_schema("does_not_exist.json")
    end
  end

  test "parse_swagger_schema/1 raises on a Swagger 2.0 document" do
    path = write_spec!(%{"swagger" => "2.0", "info" => info(), "paths" => %{}})

    assert_raise ArgumentError, ~r/OpenAPI 3\.1 or 3\.2/, fn ->
      Validator.parse_swagger_schema(path)
    end
  end

  test "multipart file properties accept uploads" do
    path =
      write_spec!(%{
        "openapi" => "3.2.0",
        "info" => info(),
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
                        "title" => %{"type" => "string"}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      })

    schemas = Map.new(Validator.parse_swagger_schema(path))
    properties = schemas["/post/uploads"].schema["properties"]

    assert %{"contentMediaType" => "application/octet-stream"} = properties["document"]
    assert %{"type" => "string"} = properties["title"]

    upload = %Plug.Upload{
      path: "/tmp/doc.pdf",
      filename: "doc.pdf",
      content_type: "application/pdf"
    }

    assert :ok =
             Validator.validate("/post/uploads", %{"document" => upload, "title" => "Notes"})

    assert {:error, message, "#/title"} =
             Validator.validate("/post/uploads", %{"document" => upload, "title" => 1})

    assert message =~ ~r/string/
  end

  test "parameter schemas may reference components" do
    path =
      write_spec!(%{
        "openapi" => "3.2.0",
        "info" => info(),
        "paths" => %{
          "/paint" => %{
            "get" => %{
              "parameters" => [
                %{
                  "name" => "color",
                  "in" => "query",
                  "schema" => %{"$ref" => "#/components/schemas/Color"}
                }
              ]
            }
          }
        },
        "components" => %{"schemas" => %{"Color" => %{"type" => "string", "enum" => ["red"]}}}
      })

    Validator.parse_swagger_schema(path)

    assert :ok = Validator.validate("/get/paint", %{"color" => "red"})
    assert {:error, message, "#/color"} = Validator.validate("/get/paint", %{"color" => "blue"})
    assert message =~ ~r/enum/
  end

  test "oneOf request bodies accept exactly one matching schema" do
    path =
      write_spec!(%{
        "openapi" => "3.2.0",
        "info" => info(),
        "paths" => %{
          "/contacts" => %{
            "post" => %{
              "requestBody" => %{
                "content" => %{
                  "application/json" => %{
                    "schema" => %{
                      "oneOf" => [
                        %{"$ref" => "#/components/schemas/Email"},
                        %{"$ref" => "#/components/schemas/Phone"}
                      ]
                    }
                  }
                }
              }
            }
          }
        },
        "components" => %{
          "schemas" => %{
            "Email" => %{"type" => "object", "required" => ["email"]},
            "Phone" => %{"type" => "object", "required" => ["phone"]}
          }
        }
      })

    Validator.parse_swagger_schema(path)

    assert :ok = Validator.validate("/post/contacts", %{"email" => "joe@example.com"})
    assert {:error, none, "#"} = Validator.validate("/post/contacts", %{"name" => "Joe"})
    assert none =~ ~r/one/

    assert {:error, both, "#"} =
             Validator.validate("/post/contacts", %{"email" => "joe@example.com", "phone" => "1"})

    assert both =~ ~r/one/
  end

  test "parse_swagger_schema/1 raises when the file is not valid JSON" do
    path = Path.join(System.tmp_dir!(), "phoenix_swagger_invalid_#{System.unique_integer()}.json")
    File.write!(path, "{not json")
    on_exit(fn -> File.rm(path) end)

    assert_raise ArgumentError, ~r/invalid JSON in swagger schema/, fn ->
      Validator.parse_swagger_schema(path)
    end
  end

  test "validate() test" do
    assert {:error, message, "#/limit"} = Validator.validate("/get/history", %{"limit" => "10"})
    assert message =~ ~r/integer/

    assert {:error, message, "#/offset"} =
             Validator.validate("/get/history", %{"limit" => 10, "offset" => "100"})

    assert message =~ ~r/integer/

    assert :ok = Validator.validate("/get/history", %{"limit" => 10, "offset" => 100})
    assert {:error, :resource_not_exists} = Validator.validate("/wrong_path", %{})

    assert :ok =
             Validator.validate("/get/estimates/time", %{
               "start_latitude" => 10,
               "start_longitude" => 20
             })

    assert {:error, message, "#/id"} = Validator.validate("/get/pets/{id}", %{"id" => "1"})
    assert message =~ ~r/integer/

    assert {:error, :resource_not_exists} = Validator.validate("/get/pets/id", %{"id" => "1"})
    assert :ok = Validator.validate("/get/pets/{id}", %{"id" => 1})
    assert {:error, :resource_not_exists} = Validator.validate("/pets", %{"id" => 1})

    assert {:error, message, "#"} = Validator.validate("/post/pets", %{})
    assert message =~ ~r/'id' and 'pet' are required/

    assert {:error, errors, "/post/pets"} =
             Validator.validate("/post/pets", %{"id" => "wrong_id"})

    assert [{type_message, "#/id"}, {required_message, "#"}] =
             Enum.sort_by(errors, &elem(&1, 1), :desc)

    assert type_message =~ ~r/integer/
    assert required_message =~ ~r/'pet' is required/

    assert {:error, message, "#"} = Validator.validate("/post/pets", %{"id" => 1})
    assert message =~ ~r/'pet' is required/

    assert {:error, message, "#/pet"} =
             Validator.validate("/post/pets", %{"id" => 1, "pet" => %{}})

    assert message =~ ~r/'name' and 'tag' are required/

    assert {:error, message, "#/pet"} =
             Validator.validate("/post/pets", %{"id" => 1, "pet" => %{"name" => "pet_name"}})

    assert message =~ ~r/'tag' is required/

    assert :ok =
             Validator.validate("/post/pets", %{
               "id" => 1,
               "pet" => %{"name" => "pet_name", "tag" => "pet_tag", "nickname" => nil}
             })

    assert :ok =
             Validator.validate("/post/pets", %{
               "id" => 1,
               "pet" => %{"name" => "pet_name", "tag" => "pet_tag", "full_name" => nil}
             })

    assert :ok =
             Validator.validate("/post/pets", %{
               "id" => 1,
               "pet" => %{
                 "name" => "pet_name",
                 "tag" => "pet_tag",
                 "full_name" => %{"first_name" => "Boaty", "last_name" => "McBoatface"}
               }
             })

    assert :ok =
             Validator.validate("/post/pets", %{
               "id" => 1,
               "pet" => %{"name" => "pet_name", "tag" => "pet_tag"}
             })
  end

  defp info, do: %{"title" => "Test", "version" => "1.0.0"}

  defp write_spec!(spec) do
    path =
      Path.join(
        System.tmp_dir!(),
        "phoenix_swagger_spec_#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(spec))
    on_exit(fn -> File.rm(path) end)
    path
  end
end
