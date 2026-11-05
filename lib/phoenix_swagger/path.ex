defmodule PhoenixSwagger.Path do
  @moduledoc """
  Defines the swagger path DSL for specifying Controller actions.

  This module should not be imported directly, it will be automatically imported
  in the scope of a `swagger_path` macro body.

  ## Examples

      use PhoenixSwagger

      swagger_path :index do
        get "/users"
        produces "application/json"
        paging
        parameter :id, :query, :integer, "user id", required: true
        tag "Users"
        response 200 "User resource" :User
        response 404 "User not found"
      end

  """

  alias PhoenixSwagger.Schema

  defmodule Parameter do
    @moduledoc """
    An OpenAPI Parameter Object. The value's type and constraints live in `schema`.

    `:body` and `:formData` parameters are Swagger 2.0 locations. They stay in the
    operation's parameter list until `PhoenixSwagger.Path.nest/1` turns them into
    a Request Body Object.

    See https://spec.openapis.org/oas/v3.2.0.html#parameter-object
    """

    defstruct(
      name: "",
      in: "",
      description: "",
      required: false,
      deprecated: nil,
      allowEmptyValue: nil,
      style: nil,
      explode: nil,
      schema: nil,
      example: nil
    )
  end

  defmodule ResponseObject do
    @moduledoc """
    A response definition, keyed by status in the operation's responses map.

    `PhoenixSwagger.Path.nest/1` renders `schema`, `example` and `examples` into
    `content`, one entry per produced media type.

    See https://spec.openapis.org/oas/v3.2.0.html#response-object
    """
    defstruct description: "", schema: nil, headers: nil, example: nil, examples: nil
  end

  defmodule OperationObject do
    @moduledoc """
    An operation ties together parameters, request body, responses, etc.

    `consumes` and `produces` are DSL inputs. They pick the media types of the
    request body and responses and never appear in the rendered operation.

    See https://spec.openapis.org/oas/v3.2.0.html#operation-object
    """
    defstruct(
      tags: [],
      summary: "",
      description: "",
      externalDocs: nil,
      operationId: "",
      consumes: nil,
      produces: nil,
      parameters: [],
      requestBody: nil,
      responses: %{},
      deprecated: nil,
      security: nil
    )
  end

  defmodule PathObject do
    @moduledoc """
    The DSL builds paths out of individual operations, so this is a flattened version
    of an OpenAPI Path Item.

    The `nest` function will convert this to a nested map before final
    conversion to a JSON map.

    See https://spec.openapis.org/oas/v3.2.0.html#paths-object
    """
    defstruct path: nil, verb: nil, operation: %OperationObject{}
  end

  @default_media_type "application/json"
  @form_media_types ["application/x-www-form-urlencoded", "multipart/form-data"]
  @parameter_option_keys [:required, :deprecated, :allowEmptyValue, :style, :explode, :example]
  @header_object_keys ~w(description required deprecated example examples schema content)

  @doc "Initializes a PathObject with verb \"get\" and given path"
  def get(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "get"}

  @doc "Initializes a PathObject with verb \"post\" and given path"
  def post(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "post"}

  @doc "Initializes a PathObject with verb \"put\" and given path"
  def put(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "put"}

  @doc "Initializes a PathObject with verb \"patch\" and given path"
  def patch(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "patch"}

  @doc "Initializes a PathObject with verb \"delete\" and given path"
  def delete(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "delete"}

  @doc "Initializes a PathObject with verb \"head\" and given path"
  def head(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "head"}

  @doc "Initializes a PathObject with verb \"options\" and given path"
  def options(path_obj = %PathObject{}, path), do: %{path_obj | path: path, verb: "options"}

  @doc """
  Adds the summary section to the operation of a swagger `%PathObject{}`.
  """
  def summary(path = %PathObject{}, summary) do
    put_in(path.operation.summary, summary)
  end

  @doc """
  Adds the description section to the operation of a swagger `%PathObject{}`.
  """
  def description(path = %PathObject{}, description) do
    put_in(path.operation.description, description)
  end

  @doc """
  Adds a mime-type to the consumes list of the operation of a swagger `%PathObject{}`.
  """
  def consumes(path = %PathObject{}, mimetype) do
    put_in(path.operation.consumes, (path.operation.consumes || []) ++ [mimetype])
  end

  @doc """
  Adds a mime-type to the produces list of the operation of a swagger `%PathObject{}`.
  """
  def produces(path = %PathObject{}, mimetype) do
    put_in(path.operation.produces, (path.operation.produces || []) ++ [mimetype])
  end

  @doc """
  Adds a tag to the operation of a swagger `%PathObject{}`.
  """
  def tag(path = %PathObject{}, tag) do
    put_in(path.operation.tags, path.operation.tags ++ [tag])
  end

  @doc """
  Adds the operationId section to the operation of a swagger `%PathObject{}`.
  """
  def operation_id(path = %PathObject{}, id) do
    put_in(path.operation.operationId, id)
  end

  @doc """
  Adds the security section to the operation of a swagger `%PathObject{}`.
  """
  def security(path = %PathObject{}, security) do
    put_in(path.operation.security, security)
  end

  @doc """
  Defines multiple parameters for an operation with a custom DSL syntax.

  ## Examples

      swagger_path :create do
        post "/api/v1/{team}/users"
        summary "Create a new user"
        parameters do
          user :body, Schema.ref(:User), "user attributes"
          team :path, :string, "Users team ID"
        end
        response 200, "OK", :User
      end

  """
  defmacro parameters(path, block) do
    exprs =
      case block do
        [do: {:__block__, _, exprs}] -> exprs
        [do: expr] -> [expr]
      end

    exprs
    |> Enum.map(fn {name, line, args} -> {:parameter, line, [name | args]} end)
    |> Enum.reduce(path, fn expr, acc ->
      quote do
        unquote(acc) |> unquote(expr)
      end
    end)
  end

  @doc """
  Adds a parameter to the operation of a `%PathObject{}`.

  `type` and constraint options (`format`, `items`, `minimum`, `enum`, ...) go into the
  parameter's `schema`. `required`, `deprecated`, `allowEmptyValue`, `style`, `explode`
  and `example` stay on the parameter. The Swagger 2.0 `collectionFormat` option is
  converted to `style` and `explode`.

  `:body` and `:formData` parameters become the operation's `requestBody`.
  """
  def parameter(path = %PathObject{}, name, location, type, description, opts \\ []) do
    param =
      case location do
        :body ->
          %Parameter{
            name: name,
            in: location,
            description: description,
            required: Keyword.get(opts, :required, false),
            schema: type
          }

        _ ->
          build_parameter(name, location, type, description, opts)
      end

    params = path.operation.parameters
    put_in(path.operation.parameters, params ++ [param])
  end

  defp build_parameter(name, location, type, description, opts) do
    {collection_format, opts} = Keyword.pop(opts, :collectionFormat)
    {extensions, opts} = Enum.split_with(opts, &specification_extension?/1)
    {parameter_opts, schema_opts} = Keyword.split(opts, @parameter_option_keys)

    schema =
      struct!(%Schema{type: type}, Enum.map(schema_opts, &convert_items_option_to_schema/1))

    %Parameter{name: name, in: location, description: description, schema: schema}
    |> struct!(style_options(location, type, collection_format))
    |> struct!(parameter_opts)
    |> Map.merge(Map.new(extensions))
    |> require_path_parameter()
  end

  defp specification_extension?({key, _value}), do: String.starts_with?(to_string(key), "x-")

  defp convert_items_option_to_schema({:items, items}) when is_list(items),
    do: {:items, struct!(Schema, items)}

  defp convert_items_option_to_schema(option), do: option

  defp require_path_parameter(%Parameter{in: location} = param) when location in [:path, "path"],
    do: %{param | required: true}

  defp require_path_parameter(param), do: param

  # Swagger 2.0 split arrays on commas by default. OpenAPI 3 query arrays default
  # to `explode: true` (repeated keys), so keep the comma form explicit.
  defp style_options(location, :array, nil) when location in [:query, "query"],
    do: [style: "form", explode: false]

  defp style_options(_location, _type, nil), do: []

  defp style_options(location, _type, collection_format) do
    case {to_string(location), to_string(collection_format)} do
      {location, "csv"} when location in ["path", "header"] ->
        [style: "simple"]

      {_location, "csv"} ->
        [style: "form", explode: false]

      {_location, "ssv"} ->
        [style: "spaceDelimited"]

      {_location, "pipes"} ->
        [style: "pipeDelimited"]

      {_location, "multi"} ->
        [style: "form", explode: true]

      {_location, other} ->
        raise ArgumentError, "collectionFormat #{other} has no OpenAPI 3 style"
    end
  end

  @doc """
  Adds the deprecation section to the operation of a swagger `%PathObject{}`.
  """
  def deprecated(path = %PathObject{}, status) do
    put_in(path.operation.deprecated, status)
  end

  @doc """
  Adds page size, number and offset parameters to the operation of a swagger `%PathObject{}`.

  The names default to  "page_size" and "page" for ease of use with `scriviner_ecto`, but can be overridden.

  ## Examples

      get "/api/pets/"
      paging
      response 200, "OK"

      get "/api/pets/dogs"
      paging size: "page_size", number: "count"
      response 200, "OK"

      get "/api/pets/cats"
      paging size: "limit", offset: "offset"
      response 200, "OK"

  """
  def paging(path = %PathObject{}, opts \\ [size: "page_size", number: "page"]) do
    Enum.reduce(opts, path, fn
      {:size, size}, path ->
        parameter(path, size, :query, :integer, "Number of elements per page", minimum: 1)

      {:number, number}, path ->
        parameter(path, number, :query, :integer, "Number of the page", minimum: 1)

      {:offset, offset}, path ->
        parameter(path, offset, :query, :integer, "Offset of first element in the page")
    end)
  end

  @doc """
  Adds a response to the operation of a swagger `%PathObject{}`, without a schema.
  """
  def response(path = %PathObject{}, status, description) do
    resp = %ResponseObject{description: description}
    put_in(path.operation.responses[to_string(status)], resp)
  end

  @doc """
  Adds a response to the operation of a `%PathObject{}`, with a schema.

  Optional keyword args can be provided for `headers`, `example` and `examples`.
  The response gets one `content` entry per media type in `produces`, or
  `application/json` when `produces` is never called. `examples` is the
  Swagger 2.0 form, keyed by media type.

  ## Examples

      get "/users/{id}"
      produces "application/json"
      parameter :id, :path, :integer, "user id", required: true
      response 200, "Success", :User, examples: %{"application/json": %{id: 1, name: "Joe"}}

      get "/users/{id}"
      produces "application/json"
      parameter :id, :path, :integer, "user id", required: true
      response 200, "Success", :User, example: %{id: 1, name: "Joe"}

  """
  def response(path, status, description, schema, opts \\ [])

  def response(path = %PathObject{}, status, description, schema, opts) when is_atom(schema) do
    response(path, status, description, Schema.ref(schema), opts)
  end

  def response(path = %PathObject{}, status, description, schema = %{}, opts) do
    resp = struct!(ResponseObject, [description: description, schema: schema] ++ opts)
    put_in(path.operation.responses[status |> to_string], resp)
  end

  @doc """
  Converts the `%PathObject{}` struct into the nested form of an OpenAPI Path Item.

  This is where `consumes`, `produces`, `:body` and `:formData` parameters, and
  response schemas are turned into `requestBody` and `content` maps, so the order
  of the DSL calls does not matter.
  """
  def nest(path = %PathObject{}) do
    %{path.path => %{path.verb => build_operation(path.operation)}}
  end

  defp build_operation(operation) do
    {body_params, params} = Enum.split_with(operation.parameters, &request_body_parameter?/1)

    operation
    |> Map.from_struct()
    |> Map.drop([:consumes, :produces])
    |> Map.merge(%{
      parameters: nil_if_empty(params),
      requestBody: build_request_body(operation, body_params),
      responses: build_responses(operation.responses, operation.produces)
    })
  end

  defp request_body_parameter?(%Parameter{in: location}),
    do: location in [:body, "body", :formData, "formData"]

  defp request_body_parameter?(_custom_parameter), do: false

  defp build_request_body(operation, []), do: operation.requestBody

  defp build_request_body(operation, params) do
    case Enum.split_with(params, &(&1.in in [:body, "body"])) do
      {[body], []} ->
        %{
          description: body.description,
          required: body.required,
          content: build_content(operation.consumes, %{schema: body.schema})
        }

      {[], form_params} ->
        %{
          required: Enum.any?(form_params, & &1.required),
          content: %{
            find_form_media_type(operation.consumes, form_params) => %{
              schema: build_form_schema(form_params)
            }
          }
        }

      {_body_params, _form_params} ->
        raise ArgumentError,
              "operation #{operation.operationId} must have either one :body parameter " <>
                "or :formData parameters, got both or several :body parameters"
    end
  end

  defp find_form_media_type(consumes, form_params) do
    Enum.find(consumes || [], &(&1 in @form_media_types)) ||
      if Enum.any?(form_params, &file_parameter?/1),
        do: "multipart/form-data",
        else: "application/x-www-form-urlencoded"
  end

  defp file_parameter?(%Parameter{schema: %Schema{type: type}}), do: type in [:file, "file"]
  defp file_parameter?(_param), do: false

  defp build_form_schema(form_params) do
    required = for param <- form_params, param.required, do: param.name

    %Schema{
      type: :object,
      properties: Map.new(form_params, &{&1.name, build_form_property_schema(&1)}),
      required: nil_if_empty(required)
    }
  end

  # A raw binary part has no JSON type, see "Working with Binary Data" in the spec.
  defp build_form_property_schema(param) do
    if file_parameter?(param) do
      %{description: param.description, contentMediaType: "application/octet-stream"}
    else
      %{param.schema | description: param.description}
    end
  end

  defp build_responses(responses, produces) do
    responses
    |> Map.new(fn {status, response} -> {status, build_response(response, produces)} end)
    |> nil_if_empty()
  end

  defp build_response(%ResponseObject{} = response, produces) do
    content =
      if response.schema,
        do: build_content(produces, &build_response_media_type(response, &1))

    %{
      description: response.description,
      headers: build_header_objects(response.headers),
      content: content
    }
  end

  defp build_response(response, _produces), do: response

  defp build_response_media_type(response, media_type) do
    %{schema: response.schema, example: find_response_example(response, media_type)}
  end

  defp find_response_example(%ResponseObject{examples: examples} = response, media_type)
       when is_map(examples) do
    Enum.find_value(examples, response.example, fn {key, example} ->
      if to_string(key) == media_type, do: example
    end)
  end

  defp find_response_example(response, _media_type), do: response.example

  defp build_content(media_types, media_type_object) when is_function(media_type_object, 1) do
    Map.new(media_types || [@default_media_type], &{&1, media_type_object.(&1)})
  end

  defp build_content(media_types, media_type_object) do
    build_content(media_types, fn _media_type -> media_type_object end)
  end

  # Swagger 2.0 headers put `type` and friends next to `description`.
  # A Header Object nests them under `schema`.
  defp build_header_objects(nil), do: nil

  defp build_header_objects(headers) do
    Map.new(headers, fn {name, header} -> {name, build_header_object(header)} end)
  end

  defp build_header_object(header) do
    {header_fields, schema_fields} =
      Enum.split_with(header, fn {key, _value} -> to_string(key) in @header_object_keys end)

    case schema_fields do
      [] -> Map.new(header_fields)
      _ -> Map.new([{:schema, Map.new(schema_fields)} | header_fields])
    end
  end

  defp nil_if_empty(empty) when empty == [] or empty == %{}, do: nil
  defp nil_if_empty(value), do: value
end
