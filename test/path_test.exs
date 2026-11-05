defmodule PhoenixSwagger.PathTest do
  use ExUnit.Case
  use PhoenixSwagger

  doctest PhoenixSwagger.Path

  swagger_path :show do
    get("/api/v1/users/{id}")
    summary("Get a user")
    description("Get a user by ID")
    parameter("id", :path, :string, "User ID", required: true, example: "123")
    response 200, "OK", :User
  end

  swagger_path :index do
    get("/api/v1/users")
    summary("Query for users")
    description("Query for users with paging and filtering")
    produces("application/json")
    tag("Users")
    operation_id("list_users")
    paging
    parameter("zipcode", :query, :string, "Address Zip Code", required: true, example: "90210")

    parameter("include", :query, :array, "Related resources to include in response",
      items: [type: :string, enum: [:organisation, :favourites, :purchases]],
      collectionFormat: :csv
    )

    response(200, "OK", :Users, example: %{id: 1, name: "Joe", email: "joe@gmail.com"})
    response(400, "Client Error")
  end

  swagger_path :create do
    post("/api/v1/{team}/users")
    summary("Create a new user")
    consumes("application/json")
    produces("application/json")

    parameters do
      user(:body, Schema.ref(:User), "user attributes")
      team(:path, :string, "Users team ID")
    end

    response 200, "OK", user_schema()
  end

  swagger_path :update do
    patch("/api/v1/user/{id}")
    summary("Update a users name")
    consumes("application/json")
    produces("application/json")
    parameter(:name, :query, :string, "User name change", required: true)
    response 200, "OK", %Schema{type: :string}
  end

  swagger_path :health_check do
    summary("verb and path will be taken from router")
    response 200, "OK", %Schema{type: :string}
  end

  def user_schema do
    swagger_schema do
      title("User")
      description("A user of the application")

      properties do
        name(:string, "Users name", required: true)
        id(:string, "Unique identifier", required: true)
        address(:string, "Home adress")

        preferences(
          Schema.new do
            properties do
              subscribe_to_mailing_list(:boolean, "mailing list subscription", default: true)
              send_special_offers(:boolean, "special offers list subscription", default: true)
              phone_number(:string, "specified phone", nullable: true)
            end
          end
        )
      end
    end
  end

  swagger_path :upload do
    post("/api/v1/avatars")
    parameter(:avatar, :formData, :file, "Avatar")
    parameter(:name, :formData, :string, "Name", required: true)
    response(201, "Created")
  end

  swagger_path :login do
    post("/api/v1/login")
    parameter(:email, :formData, :string, "Email")
    response(200, "OK")
  end

  swagger_path :login_multipart do
    post("/api/v1/login")
    consumes("multipart/form-data")
    parameter(:email, :formData, :string, "Email")
    response(200, "OK")
  end

  swagger_path :mixed do
    post("/api/v1/mixed")
    parameter(:user, :body, Schema.ref(:User), "User")
    parameter(:avatar, :formData, :file, "Avatar")
    response(200, "OK")
  end

  swagger_path :rate_limited do
    get("/api/v1/limited")

    response(200, "OK", :User,
      headers: %{"X-Rate-Limit" => %{type: :integer, description: "Calls per hour"}},
      examples: %{"application/json" => %{id: 1}}
    )
  end

  swagger_path :xml_late_produces do
    get("/api/v1/xml")
    response(200, "OK", :User)
    produces("application/xml")
  end

  swagger_path :no_responses do
    get("/api/v1/nothing")
    parameter(:q, :query, :string, "Query", deprecated: true)
  end

  test "swagger_path_show produces expected OpenAPI json" do
    route = %{verb: :get, path: "/api/v1/users/{id}"}

    assert swagger_path_show(route) == %{
             "/api/v1/users/{id}" => %{
               "get" => %{
                 "description" => "Get a user by ID",
                 "operationId" => "PhoenixSwagger.PathTest.show",
                 "parameters" => [
                   %{
                     "description" => "User ID",
                     "in" => "path",
                     "name" => "id",
                     "required" => true,
                     "schema" => %{"type" => "string"},
                     "example" => "123"
                   }
                 ],
                 "responses" => %{
                   "200" => %{
                     "description" => "OK",
                     "content" => %{
                       "application/json" => %{
                         "schema" => %{"$ref" => "#/components/schemas/User"}
                       }
                     }
                   }
                 },
                 "summary" => "Get a user",
                 "tags" => ["PathTest"]
               }
             }
           }
  end

  test "swagger_path_index produces expected OpenAPI json" do
    route = %{verb: :get, path: "/api/v1/users/"}

    assert swagger_path_index(route) == %{
             "/api/v1/users" => %{
               "get" => %{
                 "tags" => ["Users"],
                 "operationId" => "list_users",
                 "summary" => "Query for users",
                 "description" => "Query for users with paging and filtering",
                 "parameters" => [
                   %{
                     "description" => "Number of elements per page",
                     "in" => "query",
                     "name" => "page_size",
                     "required" => false,
                     "schema" => %{"type" => "integer", "minimum" => 1}
                   },
                   %{
                     "description" => "Number of the page",
                     "in" => "query",
                     "name" => "page",
                     "required" => false,
                     "schema" => %{"type" => "integer", "minimum" => 1}
                   },
                   %{
                     "description" => "Address Zip Code",
                     "in" => "query",
                     "name" => "zipcode",
                     "required" => true,
                     "schema" => %{"type" => "string"},
                     "example" => "90210"
                   },
                   %{
                     "description" => "Related resources to include in response",
                     "in" => "query",
                     "name" => "include",
                     "required" => false,
                     "style" => "form",
                     "explode" => false,
                     "schema" => %{
                       "type" => "array",
                       "items" => %{
                         "type" => "string",
                         "enum" => ["organisation", "favourites", "purchases"]
                       }
                     }
                   }
                 ],
                 "responses" => %{
                   "200" => %{
                     "description" => "OK",
                     "content" => %{
                       "application/json" => %{
                         "schema" => %{"$ref" => "#/components/schemas/Users"},
                         "example" => %{
                           "email" => "joe@gmail.com",
                           "id" => 1,
                           "name" => "Joe"
                         }
                       }
                     }
                   },
                   "400" => %{
                     "description" => "Client Error"
                   }
                 }
               }
             }
           }
  end

  test "swagger_path_create produces expected OpenAPI json" do
    route = %{verb: :post, path: "/api/v1/users/"}

    assert swagger_path_create(route) == %{
             "/api/v1/{team}/users" => %{
               "post" => %{
                 "description" => "",
                 "operationId" => "PhoenixSwagger.PathTest.create",
                 "requestBody" => %{
                   "description" => "user attributes",
                   "required" => false,
                   "content" => %{
                     "application/json" => %{
                       "schema" => %{"$ref" => "#/components/schemas/User"}
                     }
                   }
                 },
                 "parameters" => [
                   %{
                     "description" => "Users team ID",
                     "in" => "path",
                     "name" => "team",
                     "required" => true,
                     "schema" => %{"type" => "string"}
                   }
                 ],
                 "responses" => %{
                   "200" => %{
                     "description" => "OK",
                     "content" => %{
                       "application/json" => %{
                         "schema" => %{
                           "type" => "object",
                           "title" => "User",
                           "description" => "A user of the application",
                           "properties" => %{
                             "address" => %{
                               "description" => "Home adress",
                               "type" => "string"
                             },
                             "id" => %{
                               "description" => "Unique identifier",
                               "type" => "string"
                             },
                             "name" => %{
                               "description" => "Users name",
                               "type" => "string"
                             },
                             "preferences" => %{
                               "properties" => %{
                                 "send_special_offers" => %{
                                   "default" => true,
                                   "description" => "special offers list subscription",
                                   "type" => "boolean"
                                 },
                                 "subscribe_to_mailing_list" => %{
                                   "default" => true,
                                   "description" => "mailing list subscription",
                                   "type" => "boolean"
                                 },
                                 "phone_number" => %{
                                   "description" => "specified phone",
                                   "type" => ["string", "null"]
                                 }
                               },
                               "type" => "object"
                             }
                           },
                           "required" => ["id", "name"]
                         }
                       }
                     }
                   }
                 },
                 "summary" => "Create a new user",
                 "tags" => ["PathTest"]
               }
             }
           }
  end

  test "swagger_path_update produces expected OpenAPI json" do
    route = %{verb: :patch, path: "/api/v1/users/{id}"}

    assert swagger_path_update(route) == %{
             "/api/v1/user/{id}" => %{
               "patch" => %{
                 "description" => "",
                 "operationId" => "PhoenixSwagger.PathTest.update",
                 "parameters" => [
                   %{
                     "description" => "User name change",
                     "in" => "query",
                     "name" => "name",
                     "required" => true,
                     "schema" => %{"type" => "string"}
                   }
                 ],
                 "responses" => %{
                   "200" => %{
                     "description" => "OK",
                     "content" => %{"application/json" => %{"schema" => %{"type" => "string"}}}
                   }
                 },
                 "summary" => "Update a users name",
                 "tags" => ["PathTest"]
               }
             }
           }
  end

  test "verb and path can be inferred" do
    route = %{verb: :get, path: "/health"}

    assert swagger_path_health_check(route) == %{
             "/health" => %{
               "get" => %{
                 "description" => "",
                 "operationId" => "PhoenixSwagger.PathTest.health_check",
                 "responses" => %{
                   "200" => %{
                     "description" => "OK",
                     "content" => %{"application/json" => %{"schema" => %{"type" => "string"}}}
                   }
                 },
                 "summary" => "verb and path will be taken from router",
                 "tags" => ["PathTest"]
               }
             }
           }
  end

  test "formData with a file becomes a multipart request body" do
    operation = swagger_path_upload(%{})["/api/v1/avatars"]["post"]

    refute Map.has_key?(operation, "parameters")

    assert operation["requestBody"] == %{
             "required" => true,
             "content" => %{
               "multipart/form-data" => %{
                 "schema" => %{
                   "type" => "object",
                   "properties" => %{
                     "avatar" => %{
                       "description" => "Avatar",
                       "contentMediaType" => "application/octet-stream"
                     },
                     "name" => %{"type" => "string", "description" => "Name"}
                   },
                   "required" => ["name"]
                 }
               }
             }
           }
  end

  test "formData without a file becomes a urlencoded request body" do
    body = swagger_path_login(%{})["/api/v1/login"]["post"]["requestBody"]
    assert Map.keys(body["content"]) == ["application/x-www-form-urlencoded"]
    assert body["required"] == false
  end

  test "a form media type listed in consumes wins" do
    body = swagger_path_login_multipart(%{})["/api/v1/login"]["post"]["requestBody"]
    assert Map.keys(body["content"]) == ["multipart/form-data"]
  end

  test "mixing body and formData parameters raises" do
    assert_raise ArgumentError, ~r/body.*formData/, fn -> swagger_path_mixed(%{}) end
  end

  test "response headers become Header Objects and legacy examples move into content" do
    response = swagger_path_rate_limited(%{})["/api/v1/limited"]["get"]["responses"]["200"]

    assert response["headers"] == %{
             "X-Rate-Limit" => %{
               "description" => "Calls per hour",
               "schema" => %{"type" => "integer"}
             }
           }

    assert response["content"]["application/json"]["example"] == %{"id" => 1}
  end

  test "produces declared after a response still keys its content" do
    response = swagger_path_xml_late_produces(%{})["/api/v1/xml"]["get"]["responses"]["200"]
    assert Map.keys(response["content"]) == ["application/xml"]
  end

  test "operation without responses omits the responses key" do
    operation = swagger_path_no_responses(%{})["/api/v1/nothing"]["get"]
    refute Map.has_key?(operation, "responses")
    assert [%{"deprecated" => true}] = operation["parameters"]
  end

  defp render_query_parameter(type, opts) do
    %PhoenixSwagger.Path.PathObject{}
    |> PhoenixSwagger.Path.parameter(:ids, :query, type, "IDs", opts)
    |> then(&hd(&1.operation.parameters))
    |> PhoenixSwagger.to_json()
  end

  test "explicit style and explode win over the array default" do
    assert %{"style" => "form", "explode" => true} =
             render_query_parameter(:array, items: [type: :integer], explode: true)

    assert %{"style" => "pipeDelimited"} =
             render_query_parameter(:array, items: [type: :integer], style: "pipeDelimited")
  end

  test "parameter specification extensions pass through" do
    assert %{"x-internal" => true, "schema" => %{"type" => "string"}} =
             render_query_parameter(:string, "x-internal": true)
  end

  describe "collectionFormat maps to style and explode" do
    defp render_array_parameter(location, collection_format) do
      %PhoenixSwagger.Path.PathObject{}
      |> PhoenixSwagger.Path.parameter(:ids, location, :array, "IDs",
        items: [type: :integer],
        collectionFormat: collection_format
      )
      |> then(& &1.operation.parameters)
      |> hd()
      |> PhoenixSwagger.to_json()
    end

    test "ssv, pipes and multi" do
      assert %{"style" => "spaceDelimited"} = render_array_parameter(:query, :ssv)
      assert %{"style" => "pipeDelimited"} = render_array_parameter(:query, :pipes)
      assert %{"style" => "form", "explode" => true} = render_array_parameter(:query, :multi)
    end

    test "csv on a path parameter is simple" do
      assert %{"style" => "simple"} = render_array_parameter(:path, :csv)
    end

    test "tsv has no OpenAPI 3 equivalent" do
      assert_raise ArgumentError, ~r/tsv/, fn -> render_array_parameter(:query, :tsv) end
    end
  end

  test "default tag strips only the trailing Controller suffix" do
    path = %PhoenixSwagger.Path.PathObject{}

    assert ["ControllerAdmin"] =
             PhoenixSwagger.ensure_tag(path, MyApp.ControllerAdminController).operation.tags

    assert ["User"] = PhoenixSwagger.ensure_tag(path, MyApp.UserController).operation.tags
    assert [] = PhoenixSwagger.ensure_tag(path, MyApp.Controller).operation.tags
  end
end
