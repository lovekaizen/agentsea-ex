defmodule AgentSea.Embedder.Cohere do
  @moduledoc """
  Cohere embeddings adapter (`POST /v1/embed`) over `Req` — a remote
  `AgentSea.Embedder`.

  Options: `:api_key` (defaults to `COHERE_API_KEY`), `:model` (default
  `embed-english-v3.0`), `:input_type` (default `search_document`; use
  `search_query` for queries), `:base_url`, `:adapter`. `dimensions/0` reads
  `config :agentsea_embeddings, :cohere_dimensions` (default 1024).
  """

  @behaviour AgentSea.Embedder

  @base_url "https://api.cohere.com"

  @impl true
  def embed(texts, opts) do
    body = %{
      model: opts[:model] || "embed-english-v3.0",
      texts: texts,
      input_type: opts[:input_type] || "search_document"
    }

    case Req.post(req(opts), url: "/v1/embed", json: body) do
      {:ok, %Req.Response{status: 200, body: %{"embeddings" => embeddings}}} ->
        {:ok, embeddings}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def dimensions do
    Application.get_env(:agentsea_embeddings, :cohere_dimensions, 1024)
  end

  defp req(opts) do
    api_key = opts[:api_key] || System.get_env("COHERE_API_KEY")

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
