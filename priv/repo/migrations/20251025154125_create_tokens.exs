defmodule TokenApp.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens) do
      add :uuid, :uuid, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tokens, [:uuid])
  end
end
