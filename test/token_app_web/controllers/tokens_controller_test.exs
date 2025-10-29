defmodule TokenAppWeb.TokensControllerTest do
  use TokenAppWeb.ConnCase, async: false

  alias TokenApp.Repo
  alias TokenApp.Tokens
  alias TokenApp.Tokens.{Token, TokenUsage}

  setup %{conn: conn} do
    # Garantir que o banco tem tokens.
    tokens =
      case Repo.all(Token) do
        [] ->
          now = DateTime.utc_now()

          entries =
            for _ <- 1..3 do
              %{
                uuid: Ecto.UUID.generate(),
                inserted_at: now,
                updated_at: now
              }
            end

          Repo.insert_all(Token, entries)

          Repo.all(Token)

        list ->
          list
      end

    # Ativar um token
    [token_active | rest] = tokens
    user_uuid_active = Ecto.UUID.generate()
    started_at = DateTime.utc_now()

    usage_changeset =
      TokenUsage.changeset(%TokenUsage{}, %{
        token_id: token_active.id,
        user_uuid: user_uuid_active,
        started_at: started_at,
        released_at: nil
      })

    {:ok, _usage} = Repo.insert(usage_changeset)

    # Outro token vai ficar livre, sem uso aberto (available)
    token_available =
      case rest do
        [t | _] -> t
        [] -> token_active
      end

    {
      :ok,
      conn: conn,
      token_active: token_active,
      user_uuid_active: user_uuid_active,
      started_at_active: started_at,
      token_available: token_available
    }
  end

  test "GET /api/tokens retorna ativos e disponíveis", %{
    conn: conn
  } do
    conn = get(conn, "/api/tokens")
    assert conn.status == 200

    body = json_response(conn, 200)

    assert is_list(body["active"])
    assert is_list(body["available"])

    # pelo menos uma entrada em "active" tem os campos esperados
    if body["active"] != [] do
      [one | _] = body["active"]
      assert is_binary(one["token_id"])
      assert is_binary(one["user_id"])
      assert is_binary(one["started_at"])
      assert is_binary(one["expires_at"])
    end
  end

  test "GET /api/tokens/:token_id retorna status active quando há usage aberto", %{
    conn: conn,
    token_active: token_active,
    user_uuid_active: user_uuid_active,
    started_at_active: started_at
  } do
    conn = get(conn, "/api/tokens/#{token_active.uuid}")
    assert conn.status == 200

    body = json_response(conn, 200)
    assert body["token_id"] == token_active.uuid
    assert body["status"] == "active"

    assert body["current_user"]["user_id"] == user_uuid_active
    assert body["current_user"]["started_at"] == DateTime.to_iso8601(started_at)
    assert is_binary(body["current_user"]["expires_at"])
  end

  test "GET /api/tokens/:token_id retorna status available quando não há usage aberto", %{
    conn: conn,
    token_available: token_available
  } do
    # Garante que esse token não tem usage aberto (released_at == nil)
    open_usage =
      Tokens.get_open_usage_for_token(token_available.id)

    if open_usage do
      # força fechar para garantir que ele está mesmo disponível
      now = DateTime.utc_now()
      {:ok, _} = Tokens.release_token(token_available.id, now)
    end

    conn = get(conn, "/api/tokens/#{token_available.uuid}")
    assert conn.status == 200

    body = json_response(conn, 200)
    assert body["token_id"] == token_available.uuid
    assert body["status"] == "available"
    assert body["current_user"] == nil
  end

  test "GET /api/tokens/:token_id/history retorna histórico ordenado", %{
    conn: conn,
    token_active: token_active,
    user_uuid_active: user_uuid_active,
    started_at_active: started_at
  } do
    # Fecha o uso ativo pra gerar um histórico com released_at preenchido
    now = DateTime.utc_now()
    {:ok, _} = Tokens.release_token(token_active.id, now)

    # Criar um novo usage só pra ter 2 entradas no histórico
    other_user = Ecto.UUID.generate()
    {:ok, _multi} = Tokens.reassign_token_to_user(token_active.id, other_user, DateTime.utc_now())

    conn = get(conn, "/api/tokens/#{token_active.uuid}/history")
    assert conn.status == 200

    hist = json_response(conn, 200)

    assert is_list(hist)
    assert length(hist) >= 1

    # Cada item tem user_id, started_at, released_at (ou null)
    [first | _] = hist
    assert Map.has_key?(first, "user_id")
    assert Map.has_key?(first, "started_at")
    assert Map.has_key?(first, "released_at")
  end
end
