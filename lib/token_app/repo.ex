defmodule TokenApp.Repo do
  use Ecto.Repo,
    otp_app: :token_app,
    adapter: Ecto.Adapters.Postgres
end
