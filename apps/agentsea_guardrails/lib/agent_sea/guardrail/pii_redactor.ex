defmodule AgentSea.Guardrail.PIIRedactor do
  @moduledoc """
  Redacts personally-identifiable information by rewriting the content (a
  `{:transform, _}` outcome). Redacts emails, US SSNs, and phone numbers by
  default; configure with `:types` (any of `:email`, `:ssn`, `:phone`).
  """
  @behaviour AgentSea.Guardrail

  @patterns %{
    email: ~r/[\w.+-]+@[\w-]+\.[\w.-]+/,
    ssn: ~r/\b\d{3}-\d{2}-\d{4}\b/,
    phone: ~r/\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b/
  }

  @default_types [:email, :ssn, :phone]

  @impl true
  def name, do: "pii_redactor"

  @impl true
  def check(content, opts) do
    types = Keyword.get(opts, :types, @default_types)

    redacted =
      Enum.reduce(types, content, fn type, acc ->
        Regex.replace(@patterns[type], acc, "[#{String.upcase(to_string(type))}]")
      end)

    if redacted == content, do: :ok, else: {:transform, redacted}
  end
end
