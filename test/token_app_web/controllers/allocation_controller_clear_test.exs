defmodule TokenAppWeb.AllocationControllerClearTest do
  use TokenAppWeb.ConnCase, async: false

  alias TokenApp.Repo
  alias TokenApp.Tokens
  alias TokenApp.Tokens.{Token, TokenUsage}

  setup %{conn: conn} do
    ensure_tokens!(2)

    # deixa tokens ativos antes de chamar /clear
    tokens = Repo.all(Token)

    Enum.each(tokens, fn token ->
      usage_changeset =
        TokenUsage.changeset(%TokenUsage{}, %{
          token_id: token.id,
          user_uuid: Ecto.UUID.generate(),
          started_at: DateTime.utc_now(),
          released_at: nil
        })

      {:ok, _} = Repo.insert(usage_changeset)
    end)

    # sobe pool isolado e injeta no conn
    {:ok, pid} = TokenApp.TokenPool.start_link(name: nil)
    conn = Plug.Conn.assign(conn, :token_pool_pid, pid)

    {:ok, conn: conn, tokens: tokens}
  end

  test "POST /api/tokens/clear libera todos os tokens ativos", %{conn: conn, tokens: tokens} do
    # antes do clear, todos os tokens têm uso aberto
    active_before =
      Enum.count(tokens, fn token ->
        Tokens.get_open_usage_for_token(token.id) != nil
      end)

    assert active_before == length(tokens)

    # chama endpoint que usa o pool injetado
    conn = post(conn, "/api/tokens/clear")
    assert conn.status == 200

    body = json_response(conn, 200)
    assert body["cleared"] == true
    assert is_integer(body["released_count"])
    assert body["released_count"] >= 1

    # depois do clear, ninguém deve estar ativo
    active_after =
      Enum.count(tokens, fn token ->
        Tokens.get_open_usage_for_token(token.id) != nil
      end)

    assert active_after == 0
  end

  defp ensure_tokens!(n) do
    count = Repo.aggregate(Token, :count, :id)

    if count < n do
      now = DateTime.utc_now()
      missing = n - count

      entries =
        for _ <- 1..missing do
          %{
            uuid: Ecto.UUID.generate(),
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(Token, entries)
    end
  end
end
