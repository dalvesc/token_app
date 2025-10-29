defmodule TokenAppWeb.AllocationControllerTest do
  use TokenAppWeb.ConnCase, async: false

  alias TokenApp.Repo
  alias TokenApp.Tokens.Token

  setup %{conn: conn} do
    # garantir tokens
    ensure_tokens!(5)

    # subir um TokenPool isolado pro teste
    {:ok, pid} = TokenApp.TokenPool.start_link(name: nil)

    # injeta esse pid no conn, pra AllocationController usar ele
    conn = Plug.Conn.assign(conn, :token_pool_pid, pid)

    {:ok, conn: conn}
  end

  test "retorna 422 se user_id inválido", %{conn: conn} do
    conn =
      post(conn, "/api/tokens/allocate", %{
        "user_id" => "isso-nao-e-uuid"
      })

    assert conn.status == 422
    assert %{"error" => "invalid user_id"} = json_response(conn, 422)
  end

  test "aloca token com user_id válido", %{conn: conn} do
    valid_user = Ecto.UUID.generate()

    conn =
      post(conn, "/api/tokens/allocate", %{
        "user_id" => valid_user
      })

    assert conn.status == 200

    body = json_response(conn, 200)
    assert is_binary(body["token_id"])
    assert body["user_id"] == valid_user
    assert body["expires_in_seconds"] == 120
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
