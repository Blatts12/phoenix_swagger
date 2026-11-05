# OpenAPI 3.2 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `phoenix_swagger` generate, serve, and validate OpenAPI 3.2.0 documents instead of Swagger 2.0 documents.

**Architecture:** The DSL keeps its public names (`swagger_path`, `swagger_schema`, `consumes`, `produces`, `parameter`, `response`). Only the JSON it emits changes. All Swagger 2.0 to OpenAPI 3.2 reshaping happens in two finalizers: `PhoenixSwagger.to_json/1` for Schema Objects and `PhoenixSwagger.Path.nest/1` for operations. The request validator switches from `ex_json_schema` (drafts 4/6/7 only) to `jsv` (JSON Schema 2020-12), because OAS 3.1+ Schema Objects are a 2020-12 superset.

**Tech Stack:** Elixir ~> 1.16, Plug ~> 1.14, Jason, `jsv ~> 0.27` (optional dep, replaces `ex_json_schema`), swagger-ui-dist 5.34.1.

**Spec:** OpenAPI Specification 3.2.0, released 2025-09-19.
Rendered: https://spec.openapis.org/oas/v3.2.0.html
Source used for this plan: https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/versions/3.2.0.md
Official document schema: https://spec.openapis.org/oas/3.2/schema/2025-09-17

## Decisions taken (confirm before execution)

| # | Decision | Default chosen | Alternative |
|---|----------|----------------|-------------|
| D1 | Target version | `openapi: "3.2.0"`. The emitted content is also valid 3.1, so only the version string ties us to 3.2. | `"3.1.2"` for tools that lag on 3.2 |
| D2 | Swagger 2.0 output | Dropped. Breaking release, `@version` goes to `0.9.0`. | Keep a 2.0 emitter beside 3.2 (doubles the code) |
| D3 | Validation engine | `jsv ~> 0.27` (2020-12). Error message text from JSON Schema checks changes. | Keep `ex_json_schema` in draft 7 mode. It silently skips `prefixItems`, `$defs`, `dependentRequired`, `unevaluated*`. |
| D4 | Swagger 2.0 keys in `swagger_info/0` | Raise `ArgumentError` naming the OAS 3.2 replacement | Auto-convert `host`/`basePath`/`schemes`/`securityDefinitions` |
| D5 | Public names | Keep `PhoenixSwagger`, `swagger_*`, `mix phx.swagger.generate` | Rename to `openapi_*` (churn for every user) |

## Spec deltas this plan implements

Each row was checked against the 3.2.0 source text. Section names refer to that document.

| Swagger 2.0 output today | OAS 3.2 output | Spec section |
|---|---|---|
| `"swagger": "2.0"` | `"openapi": "3.2.0"` | OpenAPI Object, `openapi` REQUIRED |
| `host`, `basePath`, `schemes` | `servers: [{url}]`, default `/` | OpenAPI Object `servers`, Server Object |
| `definitions` | `components.schemas`, keys match `^[a-zA-Z0-9\.\-_]+$` | Components Object |
| `$ref: #/definitions/X` | `$ref: #/components/schemas/X` | Reference Object |
| `securityDefinitions` | `components.securitySchemes` | Components Object |
| operation `consumes`/`produces` | keys of `requestBody.content` and `responses.*.content` | Request Body Object, Response Object |
| `in: body` parameter | `requestBody: {description, required, content}` | Request Body Object, `content` REQUIRED |
| `in: formData` parameters, `type: file` | `requestBody.content["multipart/form-data" or "application/x-www-form-urlencoded"].schema.properties`, file part schema `{}` plus `contentMediaType` | Considerations for File Uploads, Basic Multipart Form example |
| parameter `type`, `format`, `items`, `enum`, `minimum`... | parameter `schema: {...}`. A parameter MUST have `schema` or `content`, not both. | Parameter Object, Fixed Fields |
| `collectionFormat` csv / ssv / pipes / multi | `style`+`explode`: form+false / spaceDelimited / pipeDelimited / form+true. `tsv` has no equivalent. | Style Values table |
| `x-example` on parameters | `example` | Parameter Object, Common Fixed Fields |
| response `schema` | `content[media].schema` | Response Object |
| response `examples: {mime => value}` | `content[mime].example` | Media Type Object |
| response header `{type, description}` | Header Object `{description, schema: {type}}` | Header Object |
| `x-nullable: true` | `type: [T, "null"]`, or `anyOf` with `{type: "null"}` for a `$ref` | Schema Object, Data Types (2020-12) |
| `exclusiveMaximum: true` + `maximum: n` | `exclusiveMaximum: n` | JSON Schema Validation 2020-12 |
| array-valued `items` (tuple) | `prefixItems` | JSON Schema Core 2020-12 |
| `discriminator: "kind"` | `discriminator: {propertyName: "kind"}` | Discriminator Object |
| empty `responses: {}` | key omitted. Responses Object MUST contain at least one code, and `responses` is optional on Operation. | Responses Object, Operation Object |

A quirk worth knowing. The 3.2.0 markdown names the dialect `https://spec.openapis.org/oas/3.1/dialect/base`, while the published schema uses `https://spec.openapis.org/oas/3.2/dialect/2025-09-17`. We never emit `jsonSchemaDialect` or `$schema`, so the spec default applies and the mismatch cannot bite us.

## Global Constraints

- Emitted `openapi` value is exactly `"3.2.0"`. The official schema pattern is `^3\.2\.\d+(-.+)?$`.
- Never emit `swagger`, `host`, `basePath`, `schemes`, `definitions`, `consumes`, `produces`, `x-nullable`, `x-example`, `collectionFormat`, boolean `exclusiveMaximum`/`exclusiveMinimum`, or array-valued `items`.
- Never emit `jsonSchemaDialect` or `$schema`.
- Schema refs use `#/components/schemas/<Name>`.
- Path parameters always carry `"required" => true`.
- Elixir floor stays `~> 1.16` (jsv 0.27.0 needs `~> 1.15`).
- `jsv` is `optional: true`, like `ex_json_schema` today. `ex_json_schema` is gone from `mix.exs` and `mix.lock` after Task 7.
- CI gates: `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, `mix test`, `mix dialyzer`.
- Every new function name is verb + object (`build_request_body`, not `body`). Predicates name the condition.
- Commits: conventional commit + gitmoji, imperative, subject 50 chars or less, for example `feat: ✨ emit OpenAPI 3.2 parameters`. No `Co-Authored-By` trailer. No "Generated with" line.
- Prose in guides, README, CHANGELOG, `@moduledoc`, `@doc`: no em dashes, no en dashes, no semicolons in sentences.

## Review Focus

1. **Form body with a non-string field.** `application/x-www-form-urlencoded` body declares `age: integer`. Request `age=42` passes, `age=old` fails with a type mismatch at `#/age`. Form values arrive as strings, so JSON Schema alone would reject every integer. Owner: Task 5.
2. **Nullable schema with `enum`.** `nullable: true, enum: [:asc, :desc]` must accept `null`. In 2020-12 `enum` is checked on its own, so the emitted `enum` must contain `null`. Owner: Task 2.
3. **`response` written before `produces` in a `swagger_path`.** The response `content` is still keyed by the produced media type. DSL order must not matter. Owner: Task 3.
4. **Hand-written spec with an array query parameter and no `explode`.** The spec default for `in: query` is `style: form, explode: true`, so `?ids=1&ids=2` means `[1, 2]`. Plug keeps only the last value, so the validator must read the raw query string. Owner: Task 6.
5. **`servers` URL with a path or variables.** `https://api.example.com/v1` gives base path `/v1`. `/api/{version}` with variable default `v2` gives `/api/v2`. No `servers` gives `/`. Owner: Task 5.

---

### Task 1: JSV dependency and OAS 3.2 conformance harness

**Files:**
- Modify: `mix.exs` (deps, `elixirc_paths`, `extra_applications(:test)`)
- Modify: `mix.lock`
- Create: `test/support/fixtures/oas-3.2-schema-2025-09-17.json`
- Create: `test/support/openapi_conformance.ex`
- Create: `test/openapi_conformance_test.exs`

**Interfaces:**
- Produces: `PhoenixSwagger.OpenApiConformance.assert_valid_openapi_document(document :: map()) :: :ok`. It flunks with the normalized JSV errors when the document breaks the official 3.2 schema. Later tasks call it on every generated document and every test fixture.
- Produces: spike tests that pin the JSV calls Tasks 5 to 7 rely on: `JSV.build_init!/0`, `JSV.build_add!/2` (returns `{root_key, normalized, ctx}`), `JSV.build_key!/2` with `JSV.Ref.parse!(pointer, :root)`, `JSV.to_root!/2`, `JSV.validate(data, root, key: key)`.

- [ ] **Step 1: Add the dependency and test support path**

In `mix.exs` add `{:jsv, "~> 0.27", optional: true}` to `deps/0`. Keep `ex_json_schema` for now. Add `elixirc_paths: elixirc_paths(Mix.env())` with `["lib", "test/support"]` for `:test` and `["lib"]` otherwise. Add `:jsv` to `extra_applications(:test)`. Then run `mix deps.get`.

- [ ] **Step 2: Vendor the official schema**

```bash
curl -sSfL -o test/support/fixtures/oas-3.2-schema-2025-09-17.json \
  https://spec.openapis.org/oas/3.2/schema/2025-09-17
```

Expected: the file starts with `"$id": "https://spec.openapis.org/oas/3.2/schema/2025-09-17"`.

- [ ] **Step 3: Write the failing tests**

This file pins the harness and the JSV behaviour later tasks depend on.

```elixir
defmodule PhoenixSwagger.OpenApiConformanceTest do
  use ExUnit.Case, async: true
  import PhoenixSwagger.OpenApiConformance

  @info %{"title" => "Pets", "version" => "1.0.0"}

  test "accepts a minimal OpenAPI 3.2 document" do
    assert :ok = assert_valid_openapi_document(%{"openapi" => "3.2.0", "info" => @info, "paths" => %{}})
  end

  test "rejects a Swagger 2.0 document" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_valid_openapi_document(%{"swagger" => "2.0", "info" => @info, "paths" => %{}})
    end
  end

  test "JSV ignores OAS-only keywords" do
    assert {:ok, _root} =
             JSV.build(%{"type" => "object", "discriminator" => %{"propertyName" => "kind"}, "example" => %{}})
  end

  test "JSV validates against a components.schemas pointer" do
    document = %{
      "components" => %{
        "schemas" => %{"Pet" => %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}}
      }
    }

    {root_key, _normalized, ctx} = JSV.build_add!(JSV.build_init!(), document)
    {pet_key, ctx} = JSV.build_key!(ctx, JSV.Ref.parse!("#/components/schemas/Pet", :root))
    root = JSV.to_root!(ctx, root_key)

    assert {:ok, _} = JSV.validate(%{"name" => "Rex"}, root, key: pet_key)
    assert {:error, error} = JSV.validate(%{"name" => 1}, root, key: pet_key)
    assert inspect(JSV.normalize_error(error)) =~ "/name"
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `mix test test/openapi_conformance_test.exs`
Expected: FAIL with `module PhoenixSwagger.OpenApiConformance is not available`. The two JSV tests should already pass. If one fails, the JSV API differs from this plan. Stop and adjust Tasks 5 to 7 before going on.

- [ ] **Step 5: Implement `assert_valid_openapi_document/1` in `test/support/openapi_conformance.ex`**

Build the JSV root from the vendored schema once and cache it in `:persistent_term`. Validate, return `:ok`, or `ExUnit.Assertions.flunk/1` with `JSV.normalize_error/1` pretty-printed. If JSV raises while resolving the 2020-12 meta-schema URL, pass the embedded resolver option from JSV's `build/2` docs.

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/openapi_conformance_test.exs`
Expected: 4 tests, 0 failures. Full `mix test` still green.

- [ ] **Step 7: Commit**

```bash
git add mix.exs mix.lock test/support test/openapi_conformance_test.exs
git commit -m "test: ✅ add OpenAPI 3.2 conformance harness"
```

---

### Task 2: Schema Objects emit JSON Schema 2020-12

**Files:**
- Modify: `lib/phoenix_swagger/schema.ex` (struct field `:"x-nullable"` becomes `:nullable`, `ref/1`, `exclusive_maximum/2`, `exclusive_minimum/2`, `discriminator/2`, `nullable/2`, `property/5`, doctests)
- Modify: `lib/phoenix_swagger.ex` (`to_json/1` gains a `%Schema{}` clause, nil handling)
- Modify: `lib/phoenix_swagger/json_api.ex` (build refs with `Schema.ref/1`)
- Create: `test/schema_to_json_test.exs`
- Modify: `test/json_api_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces: `PhoenixSwagger.Schema.ref(name :: atom) :: %Schema{"$ref": "#/components/schemas/<name>"}`. Binary paths pass through unchanged.
- Produces: `%PhoenixSwagger.Schema{}` has a `nullable` field (internal, never emitted) and no `:"x-nullable"` field.
- Produces: `PhoenixSwagger.Schema.exclusive_maximum(schema, number | boolean)` and `exclusive_minimum/2`. Number is the 2020-12 form. Boolean is the legacy form, converted at render time.
- Produces: `@doc false PhoenixSwagger.Schema.to_json_schema_2020_12(%Schema{}) :: map()` with atom keys, called by `PhoenixSwagger.to_json/1` for every `%Schema{}` at any depth. Tasks 3 and 4 rely on `to_json/1` doing this.
- Produces: `PhoenixSwagger.to_json/1` drops `nil` map values but keeps `nil` list elements (needed for `enum`).

- [ ] **Step 1: Write the failing tests in `test/schema_to_json_test.exs`**

```elixir
defmodule PhoenixSwagger.SchemaToJsonTest do
  use ExUnit.Case, async: true
  alias PhoenixSwagger.Schema
  import PhoenixSwagger, only: [to_json: 1]

  test "ref points at components.schemas" do
    assert to_json(Schema.ref(:User)) == %{"$ref" => "#/components/schemas/User"}
  end

  test "nullable adds null to the type" do
    assert to_json(Schema.nullable(%Schema{type: :string}, true)) == %{"type" => ["string", "null"]}
    assert to_json(Schema.nullable(%Schema{type: [:string, :integer]}, true)) ==
             %{"type" => ["string", "integer", "null"]}
    assert to_json(Schema.nullable(%Schema{type: [:string, :null]}, true)) == %{"type" => ["string", "null"]}
  end

  test "nullable ref becomes anyOf with null" do
    assert to_json(Schema.nullable(Schema.ref(:User), true)) == %{
             "anyOf" => [%{"$ref" => "#/components/schemas/User"}, %{"type" => "null"}]
           }
  end

  test "nullable enum accepts null" do
    schema = %Schema{type: :string, enum: [:asc, :desc]} |> Schema.nullable(true)
    assert to_json(schema) == %{"type" => ["string", "null"], "enum" => ["asc", "desc", nil]}
  end

  test "nullable property option" do
    json = to_json(Schema.property(%Schema{type: :object}, :phone, :string, "Phone", nullable: true))
    assert json["properties"]["phone"] == %{"type" => ["string", "null"], "description" => "Phone"}
  end

  test "numeric exclusive bounds" do
    assert to_json(Schema.exclusive_maximum(%Schema{type: :number}, 10)) ==
             %{"type" => "number", "exclusiveMaximum" => 10}
  end

  test "legacy boolean exclusive bounds move the limit" do
    schema = %Schema{type: :number} |> Schema.maximum(128) |> Schema.exclusive_maximum(true)
    assert to_json(schema) == %{"type" => "number", "exclusiveMaximum" => 128}

    schema = %Schema{type: :number} |> Schema.minimum(16) |> Schema.exclusive_minimum(false)
    assert to_json(schema) == %{"type" => "number", "minimum" => 16}
  end

  test "tuple items become prefixItems" do
    schema = Schema.items(%Schema{type: :array}, [%Schema{type: :string}, %Schema{type: :number}])
    assert to_json(schema) == %{"type" => "array", "prefixItems" => [%{"type" => "string"}, %{"type" => "number"}]}
  end

  test "discriminator becomes a Discriminator Object" do
    json = to_json(%Schema{type: :object} |> Schema.discriminator(:pet_type))
    assert json["discriminator"] == %{"propertyName" => "pet_type"}
    assert json["required"] == ["pet_type"]
  end
end
```

In `test/json_api_test.exs`, change every expected `"#/definitions/` to `"#/components/schemas/` and every `"x-nullable" => true` on relationship `data` to the `type` list form.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/schema_to_json_test.exs test/json_api_test.exs`
Expected: FAIL. Refs still point at `#/definitions/`, and `x-nullable` is still emitted.

- [ ] **Step 3: Implement the Schema changes**

`to_json_schema_2020_12/1` runs these rewrites on one struct level. `to_json/1` recursion reaches the nested structs.
- `nullable: true` with `type` set: append `:null` to `type` unless present, and append `nil` to `enum` when `enum` is set.
- `nullable: true` with `$ref` set: replace `$ref` with `anyOf: [%Schema{"$ref": ref}, %Schema{type: :null}]`.
- `nullable: true` with neither: drop the flag, since an untyped schema already accepts `null`.
- `exclusiveMaximum: true` takes the value of `maximum` and clears `maximum`. `false` is dropped. The same goes for minimum.
- A list in `items` moves to `prefixItems`.
- `discriminator` holding an atom or string becomes `%{propertyName: name}`.

`PhoenixSwagger.to_json/1` drops `nil` map values before recursing and returns `nil` for `nil` list elements. Delete its `:null` clause so `:null` falls through to the atom clause. Then `type: [:string, :null]` renders `["string", "null"]` and a nullable `enum` renders a real JSON `null`.

`property/5` passes `nullable:` straight into the struct instead of mapping it to `x-nullable`. `JsonApi.page/1` and `JsonApi.single/1` use `Schema.ref(resource)`. Update the `nullable/2`, `ref/1`, `array/1`, `property/5` and `discriminator/2` doctests to the new struct values.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/schema_to_json_test.exs test/json_api_test.exs`
Expected: PASS. `test/path_test.exs` now fails on ref strings. Task 3 rewrites those expectations, so note the count and move on.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_swagger/schema.ex lib/phoenix_swagger.ex lib/phoenix_swagger/json_api.ex test/schema_to_json_test.exs test/json_api_test.exs
git commit -m "feat: ✨ emit JSON Schema 2020-12 schemas"
```

---

### Task 3: Operations emit OAS 3.2 parameters, request bodies and responses

**Files:**
- Modify: `lib/phoenix_swagger/path.ex` (`Parameter`, `OperationObject`, `parameter/6`, `response/5`, `nest/1`, docs)
- Modify: `lib/phoenix_swagger.ex` (moduledoc and `swagger_path` doc examples)
- Modify: `test/path_test.exs`

**Interfaces:**
- Consumes: `PhoenixSwagger.to_json/1` and `Schema.ref/1` from Task 2.
- Produces: `PhoenixSwagger.Path.nest(%PathObject{}) :: %{path => %{verb => map()}}`. After `to_json/1` the inner map is an OAS 3.2 Operation Object. It never contains `consumes` or `produces` keys.
- Produces: `%Parameter{}` fields `name, in, description, required, deprecated, allowEmptyValue, style, explode, schema, example`. `parameter/6` builds `schema` as a `%Schema{}` from the type and the constraint opts (`format items default maximum exclusiveMaximum minimum exclusiveMinimum maxLength minLength pattern maxItems minItems uniqueItems enum multipleOf`). A keyword `items:` opt becomes `struct!(Schema, items)`.
- Produces: `parameter/6` accepts `style:`, `explode:`, `deprecated:` opts. Legacy `collectionFormat:` maps per the Style Values table. `:tsv` raises `ArgumentError`.
- Produces: `%OperationObject{}` gains `requestBody: nil`. `consumes` and `produces` stay as internal fields that `nest/1` reads and drops.

- [ ] **Step 1: Rewrite the expectations in `test/path_test.exs`**

The `:show` operation must now produce this map.

```elixir
%{
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
          "content" => %{"application/json" => %{"schema" => %{"$ref" => "#/components/schemas/User"}}}
        }
      },
      "summary" => "Get a user",
      "tags" => ["PathTest"]
    }
  }
}
```

Apply the same reshaping to `:index`, `:create`, `:update`, `:health_check`.
- `include` gets `"style" => "form", "explode" => false, "schema" => %{"type" => "array", "items" => %{"type" => "string", "enum" => ["organisation", "favourites", "purchases"]}}`.
- `page_size` gets `"schema" => %{"type" => "integer", "minimum" => 1}`.
- The `:index` 200 response gets `"content" => %{"application/json" => %{"schema" => %{"$ref" => "#/components/schemas/Users"}, "example" => %{"id" => 1, "name" => "Joe", "email" => "joe@gmail.com"}}}`. The 400 response is just `%{"description" => "Client Error"}`.
- `:create` has no `in: body` parameter. It gets `"requestBody" => %{"description" => "user attributes", "required" => false, "content" => %{"application/json" => %{"schema" => %{"$ref" => "#/components/schemas/User"}}}}`.
- `phone_number` is `%{"type" => ["string", "null"], "description" => "specified phone"}`.
- No operation has `"produces"` or `"consumes"`.

Then add these new tests, one `swagger_path` each, asserting the exact fragment:
- `formData` with `:file`: `parameter(:avatar, :formData, :file, "Avatar")` plus `parameter(:name, :formData, :string, "Name", required: true)` gives `requestBody.content["multipart/form-data"].schema == %{"type" => "object", "properties" => %{"avatar" => %{"description" => "Avatar", "contentMediaType" => "application/octet-stream"}, "name" => %{"type" => "string", "description" => "Name"}}, "required" => ["name"]}` and `requestBody.required == true`.
- `formData` without file: media type `application/x-www-form-urlencoded`. A form type listed in `consumes` wins.
- Mixing `:body` and `:formData` in one operation raises `ArgumentError` with a message matching `~r/body.*formData/`.
- Response headers: `headers: %{"X-Rate-Limit" => %{type: :integer, description: "Calls per hour"}}` emits `%{"X-Rate-Limit" => %{"description" => "Calls per hour", "schema" => %{"type" => "integer"}}}`.
- Legacy `examples: %{"application/json" => %{id: 1}}` emits `content["application/json"]["example"] == %{"id" => 1}`.
- **Review Focus 3:** `response 200, "OK", :User` written before `produces "application/xml"` emits a content key of `"application/xml"`.
- `collectionFormat` mapping: `:ssv` gives `"style" => "spaceDelimited"`, `:pipes` gives `"pipeDelimited"`, `:multi` gives `"style" => "form", "explode" => true`. `:csv` on a `:path` parameter gives `"style" => "simple"`. `:tsv` raises `ArgumentError`.
- An operation with no `response` has no `"responses"` key.
- `parameter(:q, :query, :string, "Query", deprecated: true)` emits `"deprecated" => true`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/path_test.exs`
Expected: FAIL on every rewritten expectation.

- [ ] **Step 3: Implement the reshaping in `parameter/6` and `nest/1`**

`parameter/6` builds the OAS 3.2 parameter right away for every location except `:body` and `:formData`. Those two stay in `operation.parameters` until `nest/1` runs. That keeps DSL order irrelevant, because `consumes` may come later. Array query parameters with no `style`/`explode`/`collectionFormat` get `style: "form", explode: false`. That keeps today's comma-split behaviour in the validator. `:example` maps to `example`, not `x-example`.

`nest/1` does the rest:
1. Partition body and form parameters out of `parameters` and build `requestBody`. JSON media types come from `consumes`, default `["application/json"]`.
2. Turn each `%ResponseObject{schema: s}` into `content`, one entry per `produces` media type, default `["application/json"]`. Attach `example` and convert headers to Header Objects.
3. Drop `consumes`, `produces`, and an empty `responses` or `parameters`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/path_test.exs test/json_api_test.exs test/schema_to_json_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_swagger/path.ex lib/phoenix_swagger.ex test/path_test.exs
git commit -m "feat: ✨ emit OpenAPI 3.2 operations"
```

---

### Task 4: Generator writes an OpenAPI 3.2 document

**Files:**
- Modify: `lib/mix/tasks/swagger.generate.ex` (`default_swagger_info/0`, `collect_info/1`, `collect_host/2`, `collect_definitions/2`, `sort_paths_and_definitions/1`, moduledoc)
- Modify: `test/swagger_generate_test.exs`
- Create: `test/support/sample_api.ex` (router plus one controller using every DSL feature from Task 3)

**Interfaces:**
- Consumes: OAS 3.2 path fragments from Task 3. `assert_valid_openapi_document/1` from Task 1.
- Produces: generated file shape `%{"openapi" => "3.2.0", "info" => ..., "servers" => [...] (optional), "paths" => ..., "components" => %{"schemas" => ...}}`. Task 5 fixtures follow this shape.
- Produces: `reject_swagger2_keys!(info :: map()) :: map()` (private). It raises `ArgumentError` naming the key and its replacement.
- Produces: `collect_servers(document, endpoint)` (private) replaces `collect_host/2`.

- [ ] **Step 1: Write the failing tests in `test/swagger_generate_test.exs`**

- Default document decodes to `%{"openapi" => "3.2.0", "info" => %{"title" => "<enter your title>", "version" => "0.0.1"}, "paths" => %{}, "components" => %{"schemas" => %{}}}`.
- The existing ordering test now reads key order from `components.schemas` (Apple, Mango, Zebra).
- Endpoint `url: [host: "localhost", port: 4000]` gives `"servers" => [%{"url" => "//localhost:4000"}]`. A scheme-relative URL keeps today's "use the scheme the document was served with" behaviour.
- Endpoint `url: [scheme: "https", host: "api.example.com", port: 443]` gives `[%{"url" => "https://api.example.com:443"}]`.
- Endpoint with `https:` config gives `[%{"url" => "https://localhost:4000"}, %{"url" => "http://localhost:4000"}]`.
- `swagger_info/0` returning `servers: [%{url: "/api"}]` keeps them, and the endpoint adds nothing.
- `swagger_info/0` returning `components: %{securitySchemes: %{bearer: %{type: "http", scheme: "bearer"}}}` keeps `securitySchemes` beside the collected `schemas`.
- Each of `basePath`, `host`, `schemes`, `swagger`, `consumes`, `produces`, `definitions`, `securityDefinitions`, `parameters`, `responses` in `swagger_info/0` raises `ArgumentError` with a message containing the key name and its replacement. Example: `~r/basePath.*servers/`.
- A `swagger_definitions/0` key `:"User Resource"` raises `ArgumentError` matching `~r/\^\[a-zA-Z0-9/`, because component keys MUST match `^[a-zA-Z0-9\.\-_]+$`.
- Conformance: generate from `test/support/sample_api.ex` and call `assert_valid_openapi_document/1` on the decoded file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/swagger_generate_test.exs`
Expected: FAIL. The output still has `"swagger" => "2.0"` and `definitions`.

- [ ] **Step 3: Implement the generator changes**

`default_swagger_info/0` returns `%{openapi: "3.2.0", info: ..., paths: %{}, components: %{schemas: %{}}}`. Run `reject_swagger2_keys!/1` on the router's `swagger_info/0` result before merging. Merge collected definitions into `components.schemas` and wrap that map with `OrderedObject.new/1`. `collect_servers/2` uses `Map.put_new(:servers, ...)` with the same `load_from_system_env` and `{:system, _}` guards as `collect_host_from_endpoint/2`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/swagger_generate_test.exs test/compile_phoenix_swagger_test.exs test/ordered_object_test.exs`
Expected: PASS, including the conformance test.

- [ ] **Step 5: Commit**

```bash
git add lib/mix/tasks/swagger.generate.ex test/swagger_generate_test.exs test/support/sample_api.ex
git commit -m "feat: ✨ generate OpenAPI 3.2 documents"
```

---

### Task 5: Validator reads OAS 3.2 documents with JSV

**Files:**
- Modify: `lib/phoenix_swagger/validator.ex`
- Modify: `lib/phoenix_swagger/conn_validator.ex` (constraint check goes through `Validator`)
- Rename and convert: `test/test_spec/swagger_test_spec*.json` and `swagger_jsonapi_test_spec.json` become `test/test_spec/openapi_test_spec*.json` and `openapi_jsonapi_test_spec.json`
- Modify: `test/validator_test.exs`, `test/conn_validator_test.exs`, `test/validate_plug_test.exs`, `test/plug/validate_test.exs`, `bench/conn_validator.exs`
- Modify: `mix.exs` (`xref.exclude` adds `JSV` and `JSV.Ref`)

**Interfaces:**
- Consumes: JSV calls pinned in Task 1. Document shape from Task 4.
- Produces (public, signatures unchanged): `Validator.parse_swagger_schema(path | [path]) :: [{resource_path, %{schema: map()}}]`. `schema` is now the raw synthesized 2020-12 map. `Validator.validate(resource_path, params)` returns the same tuple shapes as before.
- Produces: `Validator.lookup_request(method, path_info) :: {:ok, resource_path, operation, root} | {:error, :no_matching_path}`. `operation` is `%{body_key: key | nil, parameters: [descriptor]}`.
- Produces: descriptor `%{name, in, type, items, enum, required, key_path, constraints_key, style, explode}`. `in` is one of `"query" | "path" | "header" | "form"`. `style` and `explode` hold spec defaults when absent. Task 6 reads them.
- Produces: `@doc false Validator.validate_value_against_key(root, key, value) :: :ok | {:error, [{message, "#/..."}]}`. ConnValidator calls it for parameter constraints.
- Produces: `@doc false Validator.flatten_jsv_errors(JSV.ValidationError.t()) :: [{String.t(), String.t()}]`. Paths always use the `"#/a/b"` form.

- [ ] **Step 1: Convert the fixtures**

Convert each JSON fixture by hand, following the "Spec deltas" table. Add one conformance test per fixture to `test/openapi_conformance_test.exs`.

```elixir
for file <- Path.wildcard("test/test_spec/openapi_*.json") do
  test "fixture #{Path.basename(file)} is a valid OpenAPI 3.2 document" do
    assert :ok = assert_valid_openapi_document(Jason.decode!(File.read!(unquote(file))))
  end
end
```

Run: `mix test test/openapi_conformance_test.exs`
Expected: PASS for every fixture before any validator code changes.

- [ ] **Step 2: Rewrite the validator tests**

Point each test at the renamed fixtures. Keep every ConnValidator-owned message exactly as it is (`"Type mismatch. Expected Integer but got something else."`, `"Required property id was not present."`). For messages produced by JSON Schema checks, match the path exactly and the text with a regex:

```elixir
assert {:error, message, "#/limit"} = Validator.validate("/get/history", %{"limit" => "10"})
assert message =~ ~r/integer/i
```

Add these tests:
- **Review Focus 1:** urlencoded body with `age: integer`. `ConnValidator.validate/1` passes on `age=42`, and on `age=old` returns `{:error, "Type mismatch. Expected Integer but got something else.", "#/age"}`.
- **Review Focus 5:** spec with `servers: [%{"url" => "https://api.example.com/v1"}]` matches `GET /v1/pets`. Spec with `servers: [%{"url" => "/api/{version}", "variables" => %{"version" => %{"default" => "v2"}}}]` matches `GET /api/v2/pets`. Spec with no `servers` matches `GET /pets`.
- Multipart body with a file property (`contentMediaType`, no `type`) passes when the field holds a `%Plug.Upload{}`.
- Parameter `schema` with `$ref` to `#/components/schemas/Color` (enum) rejects a value outside the enum.
- `parse_swagger_schema/1` on a `"swagger": "2.0"` file raises `ArgumentError` matching `~r/OpenAPI 3\.1 or 3\.2/`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/validator_test.exs test/conn_validator_test.exs test/validate_plug_test.exs test/plug/validate_test.exs`
Expected: FAIL. The validator still reads `definitions`, `basePath`, and parameter `type`.

- [ ] **Step 4: Implement the validator on OAS 3.2 and JSV**

- Read `openapi`, `servers`, `paths`, `components`. Raise unless `openapi` matches `~r/^3\.[12]\.\d+/`.
- Base path is the path part of the first server URL after substituting each `{var}` with its `default`. No servers means `"/"`.
- Parameter type, items, enum and constraints come from `parameter["schema"]`.
- Request body: JSON media types (`application/json` or `+json`) add the body schema to the operation schema, as `in: body` did before. Form media types (`application/x-www-form-urlencoded`, `multipart/form-data`) turn each property into an `in: "form"` descriptor. `required` comes from the body schema's `required` list. That keeps form strings parsed before typing, like `formData` today.
- Put every schema the validator checks under one raw root: `components`, plus each operation schema and each parameter constraint schema under private keys. Call `build_key!/2` for each, then `to_root!/2` once, and store root and keys in `:persistent_term`. Escape `~` as `~0` and `/` as `~1` when building JSON pointers from resource paths like `/get/pets/{id}`.
- Delete `swagger_nullable_to_json_schema/1` and the `formData` file workaround. OAS 3.2 has neither concern.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test`
Expected: PASS. `test/schema_test_test.exs` still uses `ex_json_schema` and must stay green.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_swagger/validator.ex lib/phoenix_swagger/conn_validator.ex test bench mix.exs
git commit -m "feat: ✨ validate OpenAPI 3.2 requests with JSV"
```

---

### Task 6: Spec parameter serialization in the validator

**Files:**
- Modify: `lib/phoenix_swagger/validator.ex` (methods list, Path Item parameters, ignored headers)
- Modify: `lib/phoenix_swagger/conn_validator.ex` (`split_array_value/2`, raw query reading)
- Create: `test/test_spec/openapi_styles_spec.json`
- Modify: `test/conn_validator_test.exs`

**Interfaces:**
- Consumes: descriptor `style` and `explode` from Task 5.
- Produces: `ConnValidator.split_array_value(descriptor, raw_value) :: [String.t()]` (private).

- [ ] **Step 1: Write the failing tests**

Build `openapi_styles_spec.json` with one operation per case, and assert through `ConnValidator.validate/1`:
- `style: form, explode: false`, `?tags=a,b` gives tags `["a", "b"]`.
- `style: pipeDelimited`, `?tags=a|b` passes. `style: spaceDelimited`, `?tags=a%20b` passes.
- **Review Focus 4:** integer array, no `style` or `explode`. `?ids=1&ids=2` passes, and `?ids=1&ids=x` returns `{:error, "Type mismatch. Expected Integer but got something else.", "#/ids"}`.
- Path Item `parameters` apply to every operation on the path. An operation parameter with the same `name` and `in` replaces it.
- A required `Authorization` header parameter is ignored. The spec says header parameters named `Accept`, `Content-Type`, `Authorization` "SHALL be ignored".
- A Path Item with a `query` operation matches `conn.method == "QUERY"`. A `trace` operation matches `"TRACE"`.
- `in: cookie` and `in: querystring` parameters never fail a request.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/conn_validator_test.exs`
Expected: FAIL on every new case.

- [ ] **Step 3: Implement the serialization rules**

- Add `trace` and `query` to `@http_methods` in `Validator` and in `OrderedObject`.
- Merge Path Item parameters into each operation, keyed by `{name, in}`.
- Drop header descriptors whose lowercased name is `accept`, `content-type`, or `authorization`. Skip `cookie` and `querystring`.
- Split by `style`: `form` and `simple` on `","`, `spaceDelimited` on `" "`, `pipeDelimited` on `"|"`.
- For `in: query`, `style: form`, `explode: true` arrays, collect every value for the name from `URI.query_decoder(conn.query_string)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_swagger/validator.ex lib/phoenix_swagger/conn_validator.ex lib/phoenix_swagger/ordered_object.ex test
git commit -m "feat: ✨ apply OpenAPI parameter styles"
```

---

### Task 7: Response test helper on JSV, drop ex_json_schema

**Files:**
- Modify: `lib/phoenix_swagger/test/schema_test.ex`
- Modify: `test/schema_test_test.exs`
- Modify: `mix.exs` (remove `ex_json_schema` from deps, `xref.exclude`, `extra_applications(:test)`), `mix.lock`

**Interfaces:**
- Consumes: `Validator.flatten_jsv_errors/1` from Task 5.
- Produces: `PhoenixSwagger.SchemaTest.read_swagger_schema(file) :: [swagger_schema: %{root: root, keys: %{String.t() => key}}]`, where `root` comes from `JSV.to_root!/2` and each key from `JSV.build_key!/2`. The context key name `swagger_schema` stays for compatibility.
- Produces: `validate_resp_schema(conn, swagger_schema, model_name)` with the same signature, validating against `#/components/schemas/<model_name>`.

- [ ] **Step 1: Write the failing tests**

- Valid body for `User` returns the `conn`.
- Invalid body flunks with a message starting `"Response JSON does not conform to OpenAPI schema from #/components/schemas/User."` and containing `"At #/email:"`.
- Unknown model `"Nope"` flunks with `"No schema named \"Nope\" in #/components/schemas"`.
- Replace the `x-nullable` test: a `Pet` defined as `%{"type" => ["string", "null"]}` accepts a `null` body.
- The mtime and size cache test stays as it is.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/schema_test_test.exs`
Expected: FAIL. The helper still reads `#/definitions/`.

- [ ] **Step 3: Implement the helper on JSV and remove the dependency**

Build one key per entry in `components.schemas` at load time, then cache the result as today. Then remove `ex_json_schema` and run `mix deps.unlock --unused`.

- [ ] **Step 4: Run the full CI gate**

Run: `mix format --check-formatted && MIX_ENV=test mix compile --warnings-as-errors && mix test && mix dialyzer`
Expected: all pass. `grep -rn ExJsonSchema lib test mix.exs` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_swagger/test/schema_test.ex test/schema_test_test.exs mix.exs mix.lock
git commit -m "feat: ✨ validate responses with JSV"
```

---

### Task 8: Bundle swagger-ui 5.34.1

swagger-ui added OpenAPI 3.2.0 support in v5.32.0 (2026-02-27, changelog entry "oas32: add basic OpenAPI 3.2.0 support"). The bundled 5.2.0 only reads 3.0 and 3.1.

**Files:**
- Modify: `priv/static/*` (same file list as today, `swagger-initializer.js` excluded because the plug renders its own page)
- Modify: `test/plug/swaggerui_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
test "bundles a swagger-ui that reads OpenAPI 3.2" do
  version = "priv/static/package.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("version")
  assert Version.match?(version, ">= 5.32.0")
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/plug/swaggerui_test.exs`
Expected: FAIL. The version is `5.2.0`.

- [ ] **Step 3: Replace the bundle**

Unpack into an empty scratch directory, copy only the files `priv/static` already holds, and rebuild the gzip copies.

```bash
UI=$(mktemp -d) && curl -sSfL https://registry.npmjs.org/swagger-ui-dist/-/swagger-ui-dist-5.34.1.tgz | tar -xz -C "$UI"
for f in favicon-16x16.png favicon-32x32.png index.css LICENSE NOTICE oauth2-redirect.html package.json swagger-ui-bundle.js swagger-ui.css swagger-ui-standalone-preset.js; do cp "$UI/package/$f" priv/static/$f; done
for f in swagger-ui-bundle.js swagger-ui.css swagger-ui-standalone-preset.js; do gzip -9 -k -f priv/static/$f; done
```

- [ ] **Step 4: Run tests and check the UI by hand**

Run: `mix test test/plug/swaggerui_test.exs`
Expected: PASS.
Manual check: serve a document generated by Task 4 through `PhoenixSwagger.Plug.SwaggerUI` in `examples/simple`. Confirm the page renders, the server dropdown shows `//localhost:4000`, and "Try it out" on a multipart operation shows a file picker.

- [ ] **Step 5: Commit**

```bash
git add priv/static test/plug/swaggerui_test.exs
git commit -m "build: ⬆️ bundle swagger-ui 5.34.1"
```

---

### Task 9: Docs, changelog, example app, version

**Files:**
- Modify: `README.md`, `guides/*.md`, `CHANGELOG.md`, `mix.exs` (`@version "0.9.0"`, package `description`), `examples/simple/**`

- [ ] **Step 1: Update guides and README**

- Swap every Swagger 2.0 snippet for its OAS 3.2 form.
- `getting-started.md`: `basePath: "/api"` becomes `servers: [%{url: "/api"}]`. The spec link points at https://spec.openapis.org/oas/v3.2.0.html. Install line becomes `{:jsv, "~> 0.27"} # optional`.
- `reusing-swagger-parameters.md`: drop the `Authorization` header parameter, since the spec says it is ignored. Show `components.securitySchemes` plus `security` instead.
- `schema-validation.md`: show a JSON fixture in OAS 3.2 form. Add a limits section: one request body media type per operation, no `content`-based parameters, no `additionalOperations`.
- `test-helpers.md`: errors now point at `#/components/schemas/<Name>`.

Run the `Writing style` checklist from the user's CLAUDE.md on each changed file, before and after editing.

- [ ] **Step 2: Changelog and version**

Under `## Unreleased`, add a `### Breaking` list with one line per Global Constraints "never emit" item. Add the `ex_json_schema` to `jsv` swap and the D4 errors. Set `@version "0.9.0"`. Change the package description to say OpenAPI 3.2 instead of swagger.

- [ ] **Step 3: Update `examples/simple`**

Point its `mix.exs` dependency at `jsv`, convert `swagger_info/0`, and run `mix phx.swagger.generate` inside it. Then check the output from the main project, with `FILE` set to the path in the example's `swagger_files` config:

```bash
MIX_ENV=test mix run -e 'PhoenixSwagger.OpenApiConformance.assert_valid_openapi_document(Jason.decode!(File.read!(System.fetch_env!("FILE"))))'
```

Expected: exits 0 with no output.

- [ ] **Step 4: Verify docs build**

Run: `mix docs`
Expected: no warnings about missing references.

- [ ] **Step 5: Commit**

```bash
git add README.md guides CHANGELOG.md mix.exs examples
git commit -m "docs: 📝 document OpenAPI 3.2 migration"
```

---

## Out of scope (add when someone asks)

- `webhooks`, `callbacks`, `links`, `additionalOperations` DSL. Users can still pass `webhooks` through `swagger_info/0`.
- `Schema.one_of/2`, `Schema.any_of/2` helpers. The OAS 3.2 discriminator is legal with them, but `all_of/2` inheritance still works.
- `in: cookie` and `in: querystring` validation.
- Unique `operationId` enforcement. Phoenix `resources` routes PUT and PATCH to one action, so both get the same default id. That is a pre-existing violation and fixing it changes ids users may depend on.
- `Schema.example/2` moving to the 2020-12 `examples` array. `example` is deprecated in 3.2 but still valid.
