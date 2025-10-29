defmodule TokenApp.AllocHelpers do
  @moduledoc false

  # Faz n alocações sequenciais chamando diretamente o GenServer
  # e retorna lista de %{token_uuid, user_uuid}
  def allocate_many(pid, n) when is_pid(pid) and is_integer(n) and n > 0 do
    1..n
    |> Enum.map(fn i ->
      user_uuid = fake_user(i)
      {:ok, result} = GenServer.call(pid, {:allocate, user_uuid})

      %{
        token_uuid: result.token_uuid,
        user_uuid: result.user_uuid
      }
    end)
  end

  # Gera um UUID determinístico só pra teste.
  defp fake_user(_i) do
    Ecto.UUID.generate()
  end
end
