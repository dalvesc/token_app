# General application configuration
import Config

config :token_app,
  ecto_repos: [TokenApp.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :token_app, TokenAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: TokenApp.PubSub,
  live_view: [signing_salt: "AbEBr7Sw"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config.
import_config "#{config_env()}.exs"

config :token_app, TokenApp.TokenPool,
  ttl_ms: 120_000,
  sweep_interval_ms: 30_000
