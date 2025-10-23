import Config

# Configure database
config :token_app, TokenApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "token_app_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :token_app, TokenAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "X7hGDPXdpJMJ6WnF7YAmPMffgH/Fdb1i374gEUrSiHdSOz7Vm0VglhlZU2HVkgwa",
  watchers: []

config :token_app, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
