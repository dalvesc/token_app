defmodule TokenAppWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest
      import Plug.Conn

      alias TokenAppWeb.Router.Helpers, as: Routes

      @endpoint TokenAppWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TokenApp.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(TokenApp.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
