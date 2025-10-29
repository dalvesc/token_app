defmodule TokenApp.TokenPoolExpireTest do
  use TokenApp.DataCase, async: false
  @moduletag :capture_log

  alias TokenApp.Repo
  alias TokenApp.Tokens
  alias TokenApp.Tokens.Token
  alias TokenApp.TokenPool
  alias TokenApp.TestHelpers

  setup do
    # garantir que existe pelo menos 1 token no banco
    token =
      case Repo.one(Token) do
        nil ->
          now = DateTime.utc_now()

          {:ok, token} =
            %Token{}
            |> Tokens.Token.changeset(%{uuid: Ecto.UUID.generate()})
            |> Repo.insert()

          token

        t ->
          t
      end

    old_conf = Application.get_env(:token_app, TokenApp.TokenPool)

    # forçar TTL bem curto só pra este teste
    Application.put_env(:token_app, TokenApp.TokenPool,
      ttl_ms: 200,
      sweep_interval_ms: 50
    )

    {:ok, pid} = TokenPool.start_link(name: nil)

    on_exit(fn ->
      Application.put_env(:token_app, TokenApp.TokenPool, old_conf)
    end)

    {:ok, token: token, pool_pid: pid}
  end

  test "token é liberado automaticamente após TTL curto (config de teste)",
       %{token: _token, pool_pid: pid} do
    # alocar pra um usuário
    user_uuid = Ecto.UUID.generate()
    {:ok, alloc_res} = TokenPool.allocate(user_uuid, pid)

    token_uuid = alloc_res.token_uuid
    token_from_db = Tokens.get_token_by_uuid!(token_uuid)

    # sanity: logo depois da alocação ele deve estar ativo
    assert Tokens.get_open_usage_for_token(token_from_db.id) != nil

    # esperar até liberar automaticamente
    TestHelpers.wait_until(
      fn ->
        Tokens.get_open_usage_for_token(token_from_db.id) == nil
      end,
      5_000,
      50
    )

    assert Tokens.get_open_usage_for_token(token_from_db.id) == nil
  end
end
