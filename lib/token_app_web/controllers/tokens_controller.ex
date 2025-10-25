defmodule TokenAppWeb.TokensController do
  use TokenAppWeb, :controller

  alias TokenApp.{Tokens, TokenPool}

  @doc """
  GET /api/tokens

  Retorna:
  {
    "active": [
      {
        "token_id": "uuid-do-token",
        "user_id": "uuid-do-usuario",
        "started_at": "2025-10-25T14:23:10Z",
        "expires_at": "2025-10-25T14:25:10Z"
      }
    ],
    "available": [
      { "token_id": "uuid-disponivel" },
      ...
    ]
  }
  """
  def index(conn, _params) do
    %{active: active, available: available} = Tokens.list_current_state()

    active_serialized =
      Enum.map(active, fn row ->
        %{
          "token_id" => row.token_uuid,
          "user_id" => row.user_uuid,
          "started_at" => DateTime.to_iso8601(row.started_at),
          "expires_at" => DateTime.to_iso8601(add_seconds(row.started_at, 120))
        }
      end)

    available_serialized =
      Enum.map(available, fn row ->
        %{"token_id" => row.token_uuid}
      end)

    json(conn, %{
      "active" => active_serialized,
      "available" => available_serialized
    })
  end

  @doc """
  GET /api/tokens/:token_id

  Retorna:
  {
    "token_id": "uuid-do-token",
    "status": "active" | "available",
    "current_user": {
      "user_id": "...",
      "started_at": "...",
      "expires_at": "..."
    } | null
  }
  """
  def show(conn, %{"token_id" => token_uuid}) do
    case Tokens.get_token_by_uuid(token_uuid) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "token_not_found"})

      token ->
        usage = Tokens.get_open_usage_for_token(token.id)

        if usage do
          json(conn, %{
            "token_id" => token_uuid,
            "status" => "active",
            "current_user" => %{
              "user_id" => usage.user_uuid,
              "started_at" => DateTime.to_iso8601(usage.started_at),
              "expires_at" => DateTime.to_iso8601(add_seconds(usage.started_at, 120))
            }
          })
        else
          json(conn, %{
            "token_id" => token_uuid,
            "status" => "available",
            "current_user" => nil
          })
        end
    end
  end

  @doc """
  GET /api/tokens/:token_id/history

  Retorna:
  [
    {
      "user_id": "...",
      "started_at": "...",
      "released_at": "..." | null
    },
    ...
  ]
  """
  def history(conn, %{"token_id" => token_uuid}) do
    case Tokens.get_token_by_uuid(token_uuid) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "token_not_found"})

      _token ->
        history_rows = Tokens.list_usage_history_for_token(token_uuid)

        serialized =
          Enum.map(history_rows, fn row ->
            %{
              "user_id" => row.user_uuid,
              "started_at" => DateTime.to_iso8601(row.started_at),
              "released_at" =>
                if row.released_at do
                  DateTime.to_iso8601(row.released_at)
                else
                  nil
                end
            }
          end)

        json(conn, serialized)
    end
  end

  defp add_seconds(%DateTime{} = dt, sec) when is_integer(sec) do
    DateTime.add(dt, sec, :second)
  end
end
