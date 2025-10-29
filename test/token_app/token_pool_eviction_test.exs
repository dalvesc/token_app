defmodule TokenApp.TokenPoolEvictionTest do
  use TokenApp.DataCase, async: false
  @moduletag :capture_log

  alias TokenApp.Repo
  alias TokenApp.Tokens
  alias TokenApp.Tokens.Token
  alias TokenApp.AllocHelpers

  setup do
    # Garante que temos pelo menos 100 tokens criados antes do teste
    ensure_tokens!(100)

    {:ok, pid} = TokenApp.TokenPool.start_link(name: nil)

    {:ok, pool_pid: pid}
  end

  test "ao tentar alocar o 101º usuário, o pool reaproveita o token mais antigo",
       %{pool_pid: pid} do
    # 1) Alocar 100 usuários diferentes em sequência
    allocations = AllocHelpers.allocate_many(pid, 100)
    assert length(allocations) == 100

    # O primeiro allocation é o mais antigo
    first_alloc = hd(allocations)
    first_token_uuid = first_alloc.token_uuid
    first_user_uuid = first_alloc.user_uuid

    # Sanity: esse token do primeiro usuário deve estar ativo no banco agora
    token_id = get_token_id!(first_token_uuid)
    assert Tokens.get_open_usage_for_token(token_id) != nil

    # 2) Agora chega o 101º usuário e pede token
    new_user = Ecto.UUID.generate()
    {:ok, alloc_101} = GenServer.call(pid, {:allocate, new_user})

    # 3) Ele deve receber o MESMO token do primeiro usuário
    assert alloc_101.token_uuid == first_token_uuid
    assert alloc_101.user_uuid == new_user

    # 4) Conferir histórico desse token no banco
    #    Tokens.list_usage_history_for_token/1 retorna mais recente primeiro
    history = Tokens.list_usage_history_for_token(first_token_uuid)

    assert length(history) >= 2

    [latest | rest] = history

    # O mais recente deve ser do new_user e ainda estar ativo (released_at == nil)
    assert latest.user_uuid == new_user
    assert latest.released_at == nil

    # Algum registro anterior (rest) deve ser do first_user_uuid e já encerrado
    assert Enum.any?(rest, fn older ->
             older.user_uuid == first_user_uuid and not is_nil(older.released_at)
           end)
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

  defp get_token_id!(token_uuid) do
    token = Tokens.get_token_by_uuid!(token_uuid)
    token.id
  end
end
