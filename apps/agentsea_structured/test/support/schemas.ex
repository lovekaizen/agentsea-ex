defmodule AgentSea.Structured.TestSchemas.Person do
  @moduledoc "A test schema for structured extraction."
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
