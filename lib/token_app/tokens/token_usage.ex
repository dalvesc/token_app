defmodule TokenApp.Tokens.TokenUsage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "token_usages" do
    field :user_uuid, Ecto.UUID
    field :started_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec

    belongs_to :token, TokenApp.Tokens.Token

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [:user_uuid, :started_at, :released_at, :token_id])
    |> validate_required([:user_uuid, :started_at, :token_id])
  end
end
