defmodule TokenApp.Tokens.Token do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tokens" do
    field :uuid, Ecto.UUID

    has_many :usages, TokenApp.Tokens.TokenUsage

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:uuid])
    |> validate_required([:uuid])
    |> unique_constraint(:uuid)
  end
end
