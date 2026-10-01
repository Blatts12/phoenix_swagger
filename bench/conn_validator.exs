# Measures request validation speed and memory, plus the one-off spec compile.
#
#     mix run bench/conn_validator.exs

alias PhoenixSwagger.{ConnValidator, Validator}

specs = [
  "test/test_spec/swagger_test_spec.json",
  "test/test_spec/swagger_test_spec_2.json",
  "test/test_spec/swagger_test_spec_3.json",
  "test/test_spec/swagger_test_spec_4.json",
  "test/test_spec/swagger_jsonapi_test_spec.json"
]

Validator.parse_swagger_schema(specs)

build_conn = fn method, path, body_params ->
  method
  |> Plug.Test.conn(path)
  |> Map.put(:body_params, body_params)
  |> Plug.Conn.fetch_query_params()
  |> then(&Map.put(&1, :params, Map.merge(&1.query_params, body_params)))
end

query_conn =
  build_conn.(
    :get,
    "/typed/search?q=dogs&score=1.5&count=10&ids=a,b,c",
    %{}
  )

nested_query_conn =
  build_conn.(
    :get,
    "/shapes?api_key=key&filter[route]=1&filter[direction_id]=0&page[offset]=0&page[limit]=20",
    %{}
  )

body_conn =
  build_conn.(:post, "/api/pets", %{
    "id" => 1,
    "pet" => %{
      "name" => "Rex",
      "tag" => "dog",
      "full_name" => %{"first_name" => "Rex", "last_name" => "Dog"}
    }
  })

invalid_conn = build_conn.(:get, "/typed/search?count=x", %{})

for conn <- [query_conn, nested_query_conn, body_conn] do
  {:ok, _} = ConnValidator.validate(conn)
end

Benchee.run(
  %{
    "typed query params" => fn -> ConnValidator.validate(query_conn) end,
    "nested query params" => fn -> ConnValidator.validate(nested_query_conn) end,
    "JSON body with $ref" => fn -> ConnValidator.validate(body_conn) end,
    "invalid query param" => fn -> ConnValidator.validate(invalid_conn) end
  },
  time: 3,
  memory_time: 1,
  print: [configuration: false]
)

Benchee.run(
  %{"parse_swagger_schema (5 specs)" => fn -> Validator.parse_swagger_schema(specs) end},
  time: 3,
  memory_time: 1,
  print: [configuration: false]
)
