defmodule TokenApp.Repo.Migrations.CreateTokenUsages do
  use Ecto.Migration

  def change do
    create table(:token_usages) do
      add :token_id, references(:tokens, on_delete: :nothing), null: false
      add :user_uuid, :uuid, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:token_usages, [:token_id])
    create index(:token_usages, [:started_at])
    create index(:token_usages, [:released_at])
  end
end
