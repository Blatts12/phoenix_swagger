defmodule PhoenixSwagger.Schema do
  @moduledoc """
  Struct and helpers for OpenAPI Schema Objects.

  Fields follow the OpenAPI 3.2 Schema Object, which is a superset of JSON Schema 2020-12.
  `PhoenixSwagger.to_json/1` renders the struct in that dialect.

  See https://spec.openapis.org/oas/v3.2.0.html#schema-object
  """

  alias PhoenixSwagger.Schema

  @basic_types [:null, :boolean, :integer, :number, :string, :array, :object]

  defstruct [
    :"$ref",
    :format,
    :title,
    :description,
    :default,
    :multipleOf,
    :maximum,
    :exclusiveMaximum,
    :minimum,
    :exclusiveMinimum,
    :maxLength,
    :minLength,
    :pattern,
    :maxItems,
    :minItems,
    :uniqueItems,
    :enum,
    :maxProperties,
    :minProperties,
    :required,
    :type,
    :items,
    :allOf,
    :properties,
    :additionalProperties,
    :discriminator,
    :example,
    :nullable
  ]

  @doc """
  Construct a new %Schema{} struct using the schema DSL.

  This macro is similar to PhoenixSwagger.swagger_schema, except that it
  produces a Schema struct instead of a plain map with string keys.

  ## Examples

      iex> require PhoenixSwagger.Schema, as: Schema
      ...> Schema.new do
      ...>   type :object
      ...>   properties do
      ...>     name :string, "user name", required: true
      ...>     date_of_birth :string, "date of birth", format: :datetime
      ...>   end
      ...> end
      %Schema{
        type: :object,
        properties: %{
          name: %Schema {
            type: :string,
            description: "user name"
          },
          date_of_birth: %Schema {
            type: :string,
            format: :datetime,
            description: "date of birth"
          }
        },
        required: [:name]
      }

  """
  defmacro new(block) do
    exprs =
      case block do
        [do: {:__block__, _, exprs}] -> exprs
        [do: expr] -> [expr]
      end

    body =
      Enum.reduce(exprs, Macro.escape(%Schema{type: :object}), fn expr, acc ->
        quote do
          unquote(acc) |> unquote(expr)
        end
      end)

    quote do
      (fn ->
         import PhoenixSwagger.Schema
         unquote(body)
       end).()
    end
  end

  @doc """
  Construct a schema reference, using the name of a schema in `components.schemas`,
  or a complete path.

  ## Examples

      iex> PhoenixSwagger.Schema.ref(:User)
      %PhoenixSwagger.Schema{"$ref": "#/components/schemas/User"}

      iex> PhoenixSwagger.Schema.ref("../common/Error.json")
      %PhoenixSwagger.Schema{"$ref": "../common/Error.json"}

  """
  def ref(name) when is_atom(name) do
    %Schema{"$ref": "#/components/schemas/#{name}"}
  end

  def ref(path) when is_binary(path) do
    %Schema{"$ref": path}
  end

  @doc """
  Construct an array schema, where the array items schema is a ref to the given name.

  ## Examples

      iex> PhoenixSwagger.Schema.array(:User)
      %PhoenixSwagger.Schema{
        items: %PhoenixSwagger.Schema{"$ref": "#/components/schemas/User"},
        type: :array
      }

      iex> PhoenixSwagger.Schema.array(:string)
      %PhoenixSwagger.Schema{
        items: %PhoenixSwagger.Schema{type: :string},
        type: :array
      }

  """
  def array(name) when name in @basic_types do
    %Schema{
      type: :array,
      items: %Schema{
        type: name
      }
    }
  end

  def array(name) when is_atom(name) do
    %Schema{
      type: :array,
      items: ref(name)
    }
  end

  @doc """
  Sets a property of the Schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.property(:name, :string, "Full name", required: true, maxLength: 256)
      ...> |> Schema.property(:address, [:string, "null"], "Street Address")
      ...> |> Schema.property(:friends, Schema.array(:User), "Friends list", required: true)
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          friends: %PhoenixSwagger.Schema{
            type: :array,
            description: "Friends list",
            items: %PhoenixSwagger.Schema{"$ref": "#/components/schemas/User"}
          },
          address: %PhoenixSwagger.Schema{
            type: [:string, "null"],
            description: "Street Address"
          },
          name: %PhoenixSwagger.Schema{
            type: :string,
            description: "Full name",
            maxLength: 256
          }
        },
        required: [:friends, :name]
      }

  """
  def property(model, name, type_or_schema, description \\ nil, opts \\ [])

  def property(model = %Schema{type: :object}, name, type, description, opts)
      when is_atom(type) or is_list(type) do
    property(model, name, %Schema{type: type}, description, opts)
  end

  def property(model = %Schema{type: :object}, name, type = %Schema{}, description, opts) do
    {required?, opts} = Keyword.pop(opts, :required)
    property_schema = struct!(type, [description: type.description || description] ++ opts)
    properties = (model.properties || %{}) |> Map.put(name, property_schema)
    model = %{model | properties: properties}
    if required?, do: required(model, name), else: model
  end

  @doc """
  Defines multiple properties for a schema with a custom DSL syntax.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.properties do
      ...>      name :string, "Full Name", required: true
      ...>      dateOfBirth :string, "Date of birth", format: :datetime
      ...>    end
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          name: %PhoenixSwagger.Schema{
            type: :string,
            description: "Full Name",
          },
          dateOfBirth: %PhoenixSwagger.Schema{
            type: :string,
            description: "Date of birth",
            format: :datetime
          }
        },
        required: [:name]
      }

  """
  defmacro properties(model, block) do
    exprs =
      case block do
        [do: {:__block__, _, exprs}] -> exprs
        [do: expr] -> [expr]
      end

    body =
      exprs
      |> Enum.map(fn
        {:-, line, _args} = ast ->
          {:property, line, [get_dash_name(ast) | get_args(ast)]}

        {name, line, args} ->
          {:property, line, [name | args]}
      end)
      |> Enum.reduce(model, fn expr, acc ->
        quote do
          unquote(acc) |> unquote(expr)
        end
      end)

    quote do
      (fn ->
         import PhoenixSwagger.Schema
         unquote(body)
       end).()
    end
  end

  defp get_dash_name({:-, _line, [first, second]}),
    do: get_dash_name(first) <> "-" <> get_dash_name(second)

  defp get_dash_name({atom_name, _, _}), do: to_string(atom_name)

  defp get_args({:-, _line, [_first, second]}), do: get_args(second)
  defp get_args({_, _line, args}), do: args

  @doc """
  Sets the format of a Schema with `type: :string`.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string} |> Schema.format(:datetime)
      %PhoenixSwagger.Schema{type: :string, format: :datetime}

  """
  def format(model = %Schema{type: :string}, format) do
    %{model | format: format}
  end

  @doc """
  Sets the title of the schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{} |> Schema.title("User")
      %PhoenixSwagger.Schema{title: "User"}

  """
  def title(model = %Schema{}, title) when is_binary(title) do
    %{model | title: title}
  end

  @doc """
  Sets the description for the schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{} |> Schema.description("A user")
      %PhoenixSwagger.Schema{description: "A user"}

  """
  def description(model = %Schema{}, desc) when is_binary(desc) do
    %{model | description: desc}
  end

  @doc """
  Sets the default value for the schema.

  The value provided should validate against the schema sucessfully.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string, format: :datetime}
      ...> |> Schema.default("2017-01-01T00:00:00Z")
      %PhoenixSwagger.Schema{
        type: :string,
        format: :datetime,
        default: "2017-01-01T00:00:00Z"
      }

  """
  def default(model = %Schema{}, default) do
    %{model | default: default}
  end

  @doc """
  Limits a values of numeric type (:integer or :number) to multiples of the given amount.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :number}
      ...> |> Schema.multiple_of(7)
      %PhoenixSwagger.Schema{type: :number, multipleOf: 7}

  """
  def multiple_of(model = %Schema{}, number) when is_number(number) do
    %{model | multipleOf: number}
  end

  @doc """
  Specifies a maximum numeric value for :integer or :number types.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :integer}
      ...> |> Schema.maximum(100)
      %PhoenixSwagger.Schema{type: :integer, maximum: 100}

  """
  def maximum(model = %Schema{}, maximum) when is_number(maximum) do
    %{model | maximum: maximum}
  end

  @doc """
  Sets an exclusive upper limit for `:integer` or `:number` types: `x < limit`.

  A boolean is the Swagger 2.0 form. `true` turns the `maximum` value into the
  exclusive limit when the schema is rendered.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :number}
      ...> |> Schema.exclusive_maximum(128)
      %PhoenixSwagger.Schema{
        type: :number,
        exclusiveMaximum: 128
      }

  """
  def exclusive_maximum(model = %Schema{}, limit) when is_number(limit) or is_boolean(limit) do
    %{model | exclusiveMaximum: limit}
  end

  @doc """
  Specifies a minimum numeric value for `:integer` or `:number` types.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :integer}
      ...> |> Schema.minimum(10)
      %PhoenixSwagger.Schema{type: :integer, minimum: 10}

  """
  def minimum(model = %Schema{}, minimum) when is_number(minimum) do
    %{model | minimum: minimum}
  end

  @doc """
  Sets an exclusive lower limit for `:integer` or `:number` types: `x > limit`.

  A boolean is the Swagger 2.0 form. `true` turns the `minimum` value into the
  exclusive limit when the schema is rendered.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :number}
      ...> |> Schema.exclusive_minimum(16)
      %PhoenixSwagger.Schema{
        type: :number,
        exclusiveMinimum: 16
      }

  """
  def exclusive_minimum(model = %Schema{}, limit) when is_number(limit) or is_boolean(limit) do
    %{model | exclusiveMinimum: limit}
  end

  @doc """
  Constrains the maximum length of a string to the given value.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string}
      ...> |> Schema.max_length(255)
      %PhoenixSwagger.Schema{type: :string, maxLength: 255}

  """
  def max_length(model = %Schema{type: :string}, value) when is_number(value) and value >= 0 do
    %{model | maxLength: value}
  end

  @doc """
  Constrains the minimum length of a string to the given value.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string}
      ...> |> Schema.min_length(32)
      %PhoenixSwagger.Schema{type: :string, minLength: 32}

  """
  def min_length(model = %Schema{type: :string}, value) when is_number(value) and value >= 0 do
    %{model | minLength: value}
  end

  @doc """
  Restricts a string schema to match a regular expression, given as a string.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string}
      ...> |> Schema.pattern(~S"^(\([0-9]{2}\))?[0-9]{4}-[0-9]{4}$")
      %PhoenixSwagger.Schema{type: :string, pattern: ~S"^(\([0-9]{2}\))?[0-9]{4}-[0-9]{4}$"}

  """
  def pattern(model = %Schema{type: :string}, regex_pattern) when is_binary(regex_pattern) do
    %{model | pattern: regex_pattern}
  end

  @doc """
  Restricts the maximimum number of items in an `array` schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :array}
      ...> |> Schema.max_items(25)
      %PhoenixSwagger.Schema{type: :array, maxItems: 25}

  """
  def max_items(model = %Schema{type: :array}, value) when is_number(value) and value >= 0 do
    %{model | maxItems: value}
  end

  @doc """
  Restricts the minimum number of items in an `array` schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :array}
      ...> |> Schema.min_items(1)
      %PhoenixSwagger.Schema{type: :array, minItems: 1}

  """
  def min_items(model = %Schema{type: :array}, value) when is_number(value) and value >= 0 do
    %{model | minItems: value}
  end

  @doc """
  Boolean that when true, requires each item of an `array` schema to be unique.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :array}
      ...> |> Schema.unique_items(true)
      %PhoenixSwagger.Schema{type: :array, uniqueItems: true}

  """
  def unique_items(model = %Schema{type: :array}, unique?) when is_boolean(unique?) do
    %{model | uniqueItems: unique?}
  end

  @doc """
  Restricts the schema to a fixed set of values.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string}
      ...> |> Schema.enum(["red", "yellow", "green"])
      %PhoenixSwagger.Schema{type: :string, enum: ["red", "yellow", "green"]}

  """
  def enum(model = %Schema{}, values) when is_list(values) do
    %{model | enum: values}
  end

  @doc """
  Limits the maximum number of properties an `object` schema may contain.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.max_properties(10)
      %PhoenixSwagger.Schema{type: :object, maxProperties: 10}

  """
  def max_properties(model = %Schema{}, value) when is_number(value) and value >= 0 do
    %{model | maxProperties: value}
  end

  @doc """
  Limits the minimum number of properties an `object` schema may contain.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.min_properties(1)
      %PhoenixSwagger.Schema{type: :object, minProperties: 1}

  """
  def min_properties(model = %Schema{}, value) when is_number(value) and value >= 0 do
    %{model | minProperties: value}
  end

  @doc """
  Sets the type of for the schema.

  Valid values are `:string`, `:integer`, `:number`, `:object`, `:array`, `:boolean`, `:null`,
  or a list of those basic types.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{}
      ...> |> Schema.type(:string)
      %PhoenixSwagger.Schema{type: :string}

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{}
      ...> |> Schema.type([:string, :integer])
      %PhoenixSwagger.Schema{type: [:string, :integer]}

  """
  def type(model = %Schema{}, type) when is_atom(type) or is_list(type) do
    %{model | type: type}
  end

  @doc """
  Sets the schema/s for the items of an array.

  Use a single schema for arrays when each item should have the same schema.
  Use a list of schemas when the array represents a tuple, each element will be validated against
  the corresponding schema in the `items` list.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :array}
      ...> |> Schema.items(%Schema{type: :string})
      %PhoenixSwagger.Schema{type: :array, items: %PhoenixSwagger.Schema{type: :string}}

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :array}
      ...> |> Schema.items([%Schema{type: :string}, %Schema{type: :number}])
      %PhoenixSwagger.Schema{
        type: :array,
        items: [%PhoenixSwagger.Schema{type: :string}, %PhoenixSwagger.Schema{type: :number}]
      }

  """
  def items(model = %Schema{type: :array}, item_schema)
      when is_map(item_schema) or is_list(item_schema) do
    %{model | items: item_schema}
  end

  @doc """
  Used to combine multiple schemas, requiring a value to conform to all schemas.

  Can be used in conjunction with `discriminator` to define polymorphic inheritance relationships.

  See https://spec.openapis.org/oas/v3.2.0.html#composition-and-inheritance-polymorphism

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{}
      ...> |> Schema.all_of([Schema.ref(:Contact), Schema.ref(:CreditHistory)])
      %PhoenixSwagger.Schema{
        allOf: [
          %PhoenixSwagger.Schema{"$ref": "#/components/schemas/Contact"},
          %PhoenixSwagger.Schema{"$ref": "#/components/schemas/CreditHistory"},
        ]
      }

  """
  def all_of(model = %Schema{}, schemas) when is_list(schemas) do
    %{model | allOf: schemas}
  end

  @doc """
  Boolean indicating that additional properties are allowed, or
  a schema to be used for validating any additional properties not listed in `properties`.

  Default behaviour is to allow additional properties.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.property(:name, :string, "Full name", maxLength: 255)
      ...> |> Schema.additional_properties(false)
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          name: %PhoenixSwagger.Schema{
            type: :string,
            description: "Full name",
            maxLength: 255
          }
        },
        additionalProperties: false
      }

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object}
      ...> |> Schema.property(:name, :string, "Full name", maxLength: 255)
      ...> |> Schema.additional_properties(%Schema{type: :number})
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          name: %PhoenixSwagger.Schema{
            type: :string,
            description: "Full name",
            maxLength: 255
          }
        },
        additionalProperties: %PhoenixSwagger.Schema{
          type: :number
        }
      }

  """
  def additional_properties(model = %Schema{type: :object}, bool_or_schema) do
    %{model | additionalProperties: bool_or_schema}
  end

  @doc """
  Makes one or more properties required in an object schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object, properties: %{phone_number: %Schema{type: :string}}}
      ...> |> Schema.required(:phone_number)
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          phone_number: %PhoenixSwagger.Schema{
            type: :string
          }
        },
        required: [:phone_number]
      }

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object, properties: %{phone_number: %Schema{type: :string}, address: %Schema{type: :string}}}
      ...> |> Schema.required([:phone_number, :address])
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          phone_number: %PhoenixSwagger.Schema{
            type: :string
          },
          address: %PhoenixSwagger.Schema{
            type: :string
          }
        },
        required: [:phone_number, :address]
      }

  """
  def required(model = %Schema{type: :object}, name) when is_atom(name) or is_binary(name) do
    required(model, [name])
  end

  def required(model = %Schema{type: :object}, names) when is_list(names) do
    %{model | required: names ++ (model.required || [])}
  end

  @doc """
  Adds an example of the schema.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :object, properties: %{phone_number: %Schema{type: :string}}}
      ...> |> Schema.example(%{phone_number: "555-123-456"})
      %PhoenixSwagger.Schema{
        type: :object,
        properties: %{
          phone_number: %PhoenixSwagger.Schema{
            type: :string
          }
        },
        example: %{phone_number: "555-123-456"}
      }

  """
  def example(model = %Schema{}, example) do
    %{model | example: example}
  end

  @doc """
  Specifies the name of a property that identifies the polymorphic schema for a JSON object.

  The value of this property should be the name of this schema, or another schema that inherits
  from this schema using `all_of`. It renders as a Discriminator Object with `propertyName` set.

  See https://spec.openapis.org/oas/v3.2.0.html#discriminator-object


  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{}
      ...> |> Schema.type(:object)
      ...> |> Schema.title("Pet")
      ...> |> Schema.property(:pet_type, :string, "polymorphic pet schema type", example: "Dog")
      ...> |> Schema.discriminator(:pet_type)
      %Schema{
        type: :object,
        title: "Pet",
        properties: %{
          pet_type: %Schema{
            type: :string,
            description: "polymorphic pet schema type",
            example: "Dog"
          }
        },
        discriminator: :pet_type,
        required: [:pet_type]
      }

  """
  def discriminator(model = %Schema{}, property_name) do
    model
    |> Map.put(:discriminator, property_name)
    |> required(property_name)
  end

  @doc """
  Allows `null` as a value of the schema.

  JSON Schema 2020-12 has no `nullable` keyword. When rendered, a typed schema gets
  `"null"` added to its `type` (and `nil` to its `enum`), and a `$ref` is wrapped
  in `anyOf` with `{"type": "null"}`.

  ## Examples

      iex> alias PhoenixSwagger.Schema
      ...> %Schema{type: :string} |> Schema.nullable(true)
      %Schema{
        type: :string,
        nullable: true
      }

  """
  @spec nullable(%Schema{}, maybe_boolean) :: %Schema{}
        when maybe_boolean: true | false | nil
  def nullable(model = %Schema{}, value) when value in [true, false, nil] do
    %{model | nullable: value}
  end

  @doc false
  # Rewrites one level of the struct into JSON Schema 2020-12 keywords.
  # `PhoenixSwagger.to_json/1` recurses into nested schemas.
  def to_json_schema_2020_12(%Schema{} = schema) do
    schema
    |> Map.from_struct()
    |> apply_nullable()
    |> move_exclusive_bound(:exclusiveMaximum, :maximum)
    |> move_exclusive_bound(:exclusiveMinimum, :minimum)
    |> move_tuple_items_to_prefix_items()
    |> wrap_discriminator_property_name()
  end

  defp apply_nullable(%{nullable: true, type: type} = schema) when not is_nil(type) do
    %{schema | nullable: nil, type: add_null_type(type), enum: add_null_enum_value(schema.enum)}
  end

  defp apply_nullable(%{nullable: true, "$ref": ref} = schema) when is_binary(ref) do
    schema
    |> Map.merge(%{nullable: nil, "$ref": nil})
    |> Map.put(:anyOf, [%Schema{"$ref": ref}, %Schema{type: :null}])
  end

  defp apply_nullable(schema), do: %{schema | nullable: nil}

  defp add_null_type(types) when is_list(types) do
    if Enum.any?(types, &(&1 in [:null, "null"])), do: types, else: types ++ [:null]
  end

  defp add_null_type(type) when type in [:null, "null"], do: type
  defp add_null_type(type), do: [type, :null]

  defp add_null_enum_value(nil), do: nil
  defp add_null_enum_value(values), do: if(nil in values, do: values, else: values ++ [nil])

  defp move_exclusive_bound(schema, exclusive_key, bound_key) do
    case Map.fetch!(schema, exclusive_key) do
      true -> %{schema | exclusive_key => Map.fetch!(schema, bound_key), bound_key => nil}
      false -> %{schema | exclusive_key => nil}
      _limit_or_nil -> schema
    end
  end

  defp move_tuple_items_to_prefix_items(%{items: items} = schema) when is_list(items) do
    schema |> Map.put(:items, nil) |> Map.put(:prefixItems, items)
  end

  defp move_tuple_items_to_prefix_items(schema), do: schema

  defp wrap_discriminator_property_name(%{discriminator: name} = schema)
       when is_binary(name) or (is_atom(name) and not is_nil(name)) do
    %{schema | discriminator: %{propertyName: name}}
  end

  defp wrap_discriminator_property_name(schema), do: schema
end
