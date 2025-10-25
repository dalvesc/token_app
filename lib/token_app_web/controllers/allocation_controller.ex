defmodule TokenAppWeb.AllocationController do
  use TokenAppWeb, :controller

  alias TokenApp.TokenPool
  alias TokenApp.TokenPoolBehaviour

  @doc """
  POST /api/tokens/allocate
  Body: { "user_id": "<uuid>" }
  """
  def allocate(conn, params) do
    with {:ok, user_uuid} <- fetch_user_uuid(params),
         {:ok, result} <- call_pool_allocate(conn, user_uuid) do
      json(conn, %{
        "token_id" => result.token_uuid,
        "user_id" => result.user_uuid,
        "expires_in_seconds" => div(result.expires_in_ms, 1000),
        "evicted_user" => Map.get(result, :evicted_user)
      })
    else
      {:error, :invalid_user_uuid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid user_id"})

      {:error, :no_tokens_defined} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{"error" => "no tokens in system"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{"error" => inspect(reason)})
    end
  end

  @doc """
  POST /api/tokens/clear
  """
  def clear_all(conn, _params) do
    case call_pool_clear_all(conn) do
      {:ok, %{released_count: count}} ->
        json(conn, %{
          "cleared" => true,
          "released_count" => count
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          "error" => "clear_all_failed",
          "detail" => inspect(reason)
        })
    end
  end

  defp resolve_pool_server(conn) do
    case conn.assigns[:token_pool_pid] do
      nil -> TokenPool
      pid_or_name -> pid_or_name
    end
  end

  defp call_pool_allocate(conn, user_uuid) do
    server = resolve_pool_server(conn)
    TokenPool.allocate(user_uuid, server)
  end

  defp call_pool_clear_all(conn) do
    server = resolve_pool_server(conn)
    TokenPool.clear_all(server)
  end

  defp fetch_user_uuid(%{"user_id" => uuid}) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, ok_uuid} -> {:ok, ok_uuid}
      :error -> {:error, :invalid_user_uuid}
    end
  end

  defp fetch_user_uuid(_), do: {:error, :invalid_user_uuid}
end
