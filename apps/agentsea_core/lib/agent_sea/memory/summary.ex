defmodule AgentSea.Memory.Summary do
  @moduledoc """
  Conversation memory that keeps the most recent messages verbatim and compacts
  everything older into an LLM-generated summary once a conversation grows past a
  threshold — bounding context size on long chats.

  `load/1` returns `[summary_system_message | recent_messages]` (or just the
  messages while under the threshold). Summarization runs over any
  `AgentSea.Provider`. A singleton (like `AgentSea.Memory.Buffer`): start it once
  with the provider config.

  Options: `:provider` (`{module, opts}`, required), `:model`, `:keep_recent`
  (verbatim tail, default 6), `:threshold` (default 12), `:name`.
  """

  @behaviour AgentSea.Memory
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl AgentSea.Memory
  def save(conversation_id, messages),
    do: GenServer.call(__MODULE__, {:save, conversation_id, messages})

  @impl AgentSea.Memory
  def load(conversation_id), do: GenServer.call(__MODULE__, {:load, conversation_id})

  @impl AgentSea.Memory
  def clear(conversation_id), do: GenServer.call(__MODULE__, {:clear, conversation_id})

  # --- Server ---

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       provider: Keyword.fetch!(opts, :provider),
       model: Keyword.get(opts, :model),
       keep: Keyword.get(opts, :keep_recent, 6),
       threshold: Keyword.get(opts, :threshold, 12),
       store: %{}
     }}
  end

  @impl GenServer
  def handle_call({:save, id, messages}, _from, state) do
    {:reply, :ok, %{state | store: Map.put(state.store, id, compact(messages, state))}}
  end

  def handle_call({:load, id}, _from, state) do
    {:reply, to_messages(Map.get(state.store, id)), state}
  end

  def handle_call({:clear, id}, _from, state) do
    {:reply, :ok, %{state | store: Map.delete(state.store, id)}}
  end

  # --- Compaction ---

  defp compact(messages, state) do
    if length(messages) > state.threshold do
      {older, recent} = Enum.split(messages, length(messages) - state.keep)
      %{summary: summarize(older, state), recent: recent}
    else
      %{summary: nil, recent: messages}
    end
  end

  defp summarize(messages, %{provider: {module, opts}, model: model}) do
    transcript = Enum.map_join(messages, "\n", fn m -> "#{m.role}: #{m.content}" end)

    prompt = [
      %{
        role: :system,
        content:
          "Summarize the conversation so far in 2-3 sentences, preserving key facts and decisions."
      },
      %{role: :user, content: transcript}
    ]

    case module.complete(prompt, Keyword.put(opts, :model, model)) do
      {:ok, response} -> response.content
      {:error, _reason} -> nil
    end
  end

  defp to_messages(nil), do: []
  defp to_messages(%{summary: nil, recent: recent}), do: recent

  defp to_messages(%{summary: summary, recent: recent}) do
    [%{role: :system, content: "Summary of earlier conversation: " <> summary} | recent]
  end
end
