defmodule PhoenixSwagger.SampleApi do
  @moduledoc false

  # A small API that touches every DSL feature, so generated documents can be
  # checked against the official OpenAPI 3.2 schema.

  defmodule PetController do
    @moduledoc false
    use PhoenixSwagger

    swagger_path :index do
      get("/api/pets")
      summary("List pets")
      produces("application/json")
      paging()
      parameter(:tags, :query, :array, "Filter by tags", items: [type: :string])
      parameter(:sort, :query, :string, "Sort order", enum: [:asc, :desc], example: "asc")
      parameter("X-Request-Id", :header, :string, "Request id", deprecated: true)
      security([%{bearer: []}])

      response(200, "OK", Schema.array(:Pet),
        example: [%{id: 1, name: "Rex", pet_type: "Dog"}],
        headers: %{"X-Rate-Limit" => %{type: :integer, description: "Calls per hour"}}
      )

      response(400, "Bad request", :Error)
    end

    swagger_path :show do
      get("/api/pets/{id}")
      parameter(:id, :path, :integer, "Pet id", minimum: 1)
      response(200, "OK", :Pet)
      response(404, "Not found")
    end

    swagger_path :create do
      post("/api/pets")
      consumes("application/json")
      parameter(:pet, :body, Schema.ref(:Pet), "Pet to add", required: true)
      response(201, "Created", :Pet)
    end

    swagger_path :upload_photo do
      post("/api/pets/{id}/photo")
      parameter(:id, :path, :integer, "Pet id")
      parameter(:photo, :formData, :file, "Photo", required: true)
      parameter(:caption, :formData, :string, "Caption")
      response(204, "Uploaded")
    end

    swagger_path :pay do
      post("/api/pets/{id}/payments")
      parameter(:id, :path, :integer, "Pet id")
      parameter(:payment, :body, Schema.ref(:Payment), "Payment", required: true)
      response(201, "Paid")
    end

    swagger_path :delete do
      delete("/api/pets/{id}")
      parameter(:id, :path, :integer, "Pet id")
      deprecated(true)
      response(204, "Deleted")
    end

    def swagger_definitions do
      %{
        Pet:
          swagger_schema do
            title("Pet")

            properties do
              id(:integer, "Pet id", required: true, format: :int64)
              name(:string, "Pet name", required: true, maxLength: 64)
              nickname(:string, "Nickname", nullable: true)
              owner(Schema.ref(:Owner), "Owner", nullable: true)
              weight(:number, "Weight in kg", exclusiveMinimum: 0)
              pet_type(:string, "Kind of pet", enum: [:Dog, :Cat])

              location(
                Schema.items(%Schema{type: :array}, [
                  %Schema{type: :number},
                  %Schema{type: :number}
                ]),
                "Lat, lng"
              )
            end

            discriminator(:pet_type)
          end,
        Owner:
          swagger_schema do
            properties do
              name(:string, "Owner name")
            end
          end,
        Payment:
          swagger_schema do
            title("Payment")
            one_of([Schema.ref(:Card), Schema.ref(:BankAccount)])
            discriminator(:method)
          end,
        Card:
          swagger_schema do
            properties do
              method(:string, "Payment method", required: true, enum: [:Card])
              number(:string, "Card number", required: true)
            end
          end,
        BankAccount:
          swagger_schema do
            properties do
              method(:string, "Payment method", required: true, enum: [:BankAccount])
              iban(:string, "IBAN", required: true)
            end
          end,
        Error:
          swagger_schema do
            properties do
              message(:string, "Error message", required: true)
            end
          end
      }
    end
  end

  defmodule Router do
    @moduledoc false

    def __routes__ do
      for {verb, path, action} <- [
            {:get, "/api/pets", :index},
            {:get, "/api/pets/:id", :show},
            {:post, "/api/pets", :create},
            {:post, "/api/pets/:id/photo", :upload_photo},
            {:post, "/api/pets/:id/payments", :pay},
            {:delete, "/api/pets/:id", :delete}
          ] do
        %{plug: PetController, plug_opts: action, path: path, verb: verb}
      end
    end

    def swagger_info do
      %{
        info: %{title: "Pet store", version: "1.0.0"},
        servers: [%{url: "/"}],
        tags: [%{name: "Pet", description: "Pet operations"}],
        components: %{securitySchemes: %{bearer: %{type: "http", scheme: "bearer"}}}
      }
    end
  end
end
