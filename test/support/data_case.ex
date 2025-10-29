defmodule TokenApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias TokenApp.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TokenApp.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TokenApp.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TokenApp.Repo, {:shared, self()})
    end

    :ok
  end
end
