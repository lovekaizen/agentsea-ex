defmodule AgentSea.Structured do
  @moduledoc """
  Structured output: extract a validated Ecto struct from an LLM.

  The Elixir analogue of "Zod schema → validated object" is "Ecto schema →
  validated changeset". You define an embedded schema with a `changeset/2`, and
  `extract/3` prompts a provider for JSON, casts it through the changeset, and —
  on a parse or validation error — feeds the problem back to the model and
  retries (up to `:max_retries`).

  Works over any `AgentSea.Provider` (so requests can run through the gateway)
  and needs no network in tests.

  ## Example

      defmodule Person do
        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          field :name, :string
          field :age, :integer
        end

        def changeset(struct, params) do
          struct
          |> cast(params, [:name, :age])
          |> validate_required([:name, :age])
          |> validate_number(:age, greater_than: 0)
        end
      end

      {:ok, %Person{}} =
        AgentSea.Structured.extract(Person, "Ada Lovelace, 36",
          provider: {AgentSea.Providers.Anthropic, []},
          model: "claude-opus-4-8"
        )
  """

  @type schema :: module()
  @type input :: String.t() | [AgentSea.Provider.message()]

  @doc """
  Extract a `schema` struct from `input`.

  Options:
    * `:provider`     — `{module, opts}` (required); module implements `AgentSea.Provider`
    * `:model`        — model id (or supply it in the provider opts)
    * `:max_retries`  — validation/parse retries (default 3)
    * `:system_prompt`— extra instructions, prepended to the schema instructions
  """
  @spec extract(schema(), input(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def extract(schema, input, opts) do
    {provider_mod, provider_opts} = Keyword.fetch!(opts, :provider)
    model = Keyword.get(opts, :model) || Keyword.get(provider_opts, :model)
    if is_nil(model), do: raise(ArgumentError, "a :model is required")

    max_retries = Keyword.get(opts, :max_retries, 3)
    call_opts = Keyword.put(provider_opts, :model, model)
    messages = build_messages(schema, input, opts)

    loop(schema, messages, provider_mod, call_opts, max_retries, 0)
  end

  defp loop(schema, messages, provider_mod, call_opts, max_retries, attempt) do
    case provider_mod.complete(messages, call_opts) do
      {:ok, response} ->
        validate_or_retry(
          schema,
          messages,
          provider_mod,
          call_opts,
          max_retries,
          attempt,
          response
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_or_retry(
         schema,
         messages,
         provider_mod,
         call_opts,
         max_retries,
         attempt,
         response
       ) do
    case parse_and_validate(schema, response.content) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, reason, _hint} when attempt >= max_retries ->
        {:error, reason}

      {:error, _reason, hint} ->
        retry =
          messages ++
            [
              %{role: :assistant, content: response.content},
              %{role: :user, content: hint}
            ]

        loop(schema, retry, provider_mod, call_opts, max_retries, attempt + 1)
    end
  end

  # --- Prompt building ---

  defp build_messages(schema, input, opts) do
    system = instructions(schema, opts[:system_prompt])
    [%{role: :system, content: system} | user_messages(input)]
  end

  defp user_messages(input) when is_binary(input), do: [%{role: :user, content: input}]
  defp user_messages(messages) when is_list(messages), do: messages

  defp instructions(schema, extra) do
    fields =
      Enum.map_join(field_specs(schema), "\n", fn {name, type} -> "  - #{name}: #{type}" end)

    base = """
    You are a precise data-extraction assistant. Extract the requested
    information and respond with ONLY a single JSON object — no prose, no
    markdown code fences — with exactly these fields:
    #{fields}
    """

    if extra, do: extra <> "\n\n" <> base, else: base
  end

  defp field_specs(schema) do
    for field <- schema.__schema__(:fields) do
      {field, json_type(schema.__schema__(:type, field))}
    end
  end

  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:float), do: "number"
  defp json_type(:decimal), do: "number"
  defp json_type(:boolean), do: "boolean"
  defp json_type({:array, inner}), do: "array of #{json_type(inner)}"
  defp json_type(_), do: "string"

  # --- Parsing + validation ---

  defp parse_and_validate(schema, content) do
    case extract_json(content) do
      {:ok, params} ->
        changeset = schema.changeset(struct(schema), params)

        if changeset.valid? do
          {:ok, Ecto.Changeset.apply_changes(changeset)}
        else
          errors = changeset_errors(changeset)

          {:error, {:validation, errors},
           "Your previous JSON failed validation: #{inspect(errors)}. " <>
             "Respond again with ONLY a corrected JSON object."}
        end

      :error ->
        {:error, :invalid_json,
         "Your previous response was not valid JSON. Respond with ONLY a single JSON object."}
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Pull a JSON object out of the model's content (handles bare JSON, fenced
  # blocks, and JSON embedded in prose).
  defp extract_json(content) do
    candidate =
      content
      |> String.trim()
      |> strip_fences()
      |> first_object()

    case Jason.decode(candidate) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> :error
    end
  end

  defp strip_fences(string) do
    case Regex.run(~r/```(?:json)?\s*(.*?)\s*```/s, string) do
      [_, inner] -> inner
      _ -> string
    end
  end

  defp first_object(string) do
    with {open, _} <- :binary.match(string, "{"),
         close when is_integer(close) <- last_brace(string) do
      binary_part(string, open, close - open + 1)
    else
      _ -> string
    end
  end

  defp last_brace(string) do
    case :binary.matches(string, "}") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end
end
