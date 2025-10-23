import Config

config :token_app, TokenApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "token_app_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :token_app, TokenApp.TokenPool,
  ttl_ms: 200,
  sweep_interval_ms: 100

config :logger, level: :warn
