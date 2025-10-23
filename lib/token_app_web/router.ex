defmodule TokenAppWeb.Router do
  use TokenAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TokenAppWeb do
    pipe_through :api

    # alocação e limpeza
    post "/tokens/allocate", AllocationController, :allocate
    post "/tokens/clear", AllocationController, :clear_all

    # info dos tokens
    get "/tokens", TokensController, :index
    get "/tokens/:token_id", TokensController, :show
    get "/tokens/:token_id/history", TokensController, :history
  end
end
