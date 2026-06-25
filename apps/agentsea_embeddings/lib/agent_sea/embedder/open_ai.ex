defmodule AgentSea.Embedder.OpenAI do
  @moduledoc """
  OpenAI embeddings adapter (`POST /v1/embeddings`) over `Req` — a remote
  `AgentSea.Embedder` (no local model).

  Options: `:api_key` (defaults to `OPENAI_API_KEY`), `:model` (default
  `text-embedding-3-small`), `:base_url`, `:adapter` (a Req adapter for tests).
  `dimensions/0` reads `config :agentsea_embeddings, :openai_dimensions` (default
  1536 — must match the model).
  """

  @behaviour AgentSea.Embedder

  @base_url "https://api.openai.com"

  @impl true
  def embed(texts, opts) do
    body = %{model: opts[:model] || "text-embedding-3-small", input: texts}

    case Req.post(req(opts), url: "/v1/embeddings", json: body) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        # Preserve input order via the response index.
        vectors = data |> Enum.sort_by(& &1["index"]) |> Enum.map(& &1["embedding"])
        {:ok, vectors}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def dimensions do
    Application.get_env(:agentsea_embeddings, :openai_dimensions, 1536)
  end

  defp req(opts) do
    api_key = opts[:api_key] || System.get_env("OPENAI_API_KEY")

    [
      base_url: opts[:base_url] || @base_url,
      headers: [{"authorization", "Bearer #{api_key || ""}"}]
    ]
    |> maybe_put(:adapter, opts[:adapter])
    |> Req.new()
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
