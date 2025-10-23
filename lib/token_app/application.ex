defmodule TokenApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      TokenApp.Repo,
      {Phoenix.PubSub, name: TokenApp.PubSub},
      TokenAppWeb.Endpoint,
      TokenApp.TokenPool
    ]

    opts = [strategy: :one_for_one, name: TokenApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    TokenAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
