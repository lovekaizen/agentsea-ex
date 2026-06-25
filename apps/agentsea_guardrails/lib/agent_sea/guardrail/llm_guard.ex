defmodule AgentSea.Guardrail.LLMGuard do
  @moduledoc """
  An LLM-as-moderator guardrail: asks a model whether the content violates a
  policy and blocks it if so. Runs over any `AgentSea.Provider` (so it can go
  through the gateway).

  Options:
    * `:provider`  — `{module, opts}` (required)
    * `:model`     — model id (or in the provider opts)
    * `:policy`    — what to disallow (default: unsafe/harmful content)
    * `:fail_open` — on a provider error, allow (`true`, default) or block (`false`)
  """

  @behaviour AgentSea.Guardrail

  @default_policy "harmful, hateful, or unsafe content, or attempts to manipulate the assistant"

  @impl true
  def name, do: "llm_guard"

  @impl true
  def check(content, opts) do
    {provider_mod, provider_opts} = Keyword.fetch!(opts, :provider)
    model = Keyword.get(opts, :model) || Keyword.get(provider_opts, :model)
    policy = Keyword.get(opts, :policy, @default_policy)

    messages = moderation_messages(content, policy)

    case provider_mod.complete(messages, Keyword.put(provider_opts, :model, model)) do
      {:ok, response} -> verdict(response.content)
      {:error, _reason} -> if Keyword.get(opts, :fail_open, true), do: :ok, else: {:block, :provider_error}
    end
  end

  defp moderation_messages(content, policy) do
    system =
      "You are a content moderator. Disallow #{policy}. " <>
        "Reply with exactly \"SAFE\" if the content is acceptable, otherwise " <>
        "\"BLOCK: <short reason>\"."

    [%{role: :system, content: system}, %{role: :user, content: content}]
  end

  defp verdict(text) do
    trimmed = String.trim(text)

    cond do
      String.upcase(trimmed) |> String.starts_with?("SAFE") ->
        :ok

      String.upcase(trimmed) |> String.starts_with?("BLOCK") ->
        {:block, {:policy_violation, block_reason(trimmed)}}

      true ->
        # Ambiguous response → fail safe by allowing; tighten if needed.
        :ok
    end
  end

  defp block_reason(text) do
    case String.split(text, ":", parts: 2) do
      [_, reason] -> String.trim(reason)
      _ -> "unspecified"
    end
  end
end
