defmodule TokenApp.TokenPool do
  @moduledoc """
  Processo responsável por gerenciar a alocação de tokens de forma segura.

  Ele é o único ponto que decide:
    - qual token vai para qual usuário
    - quem é o mais antigo (para fazer liberação)
    - quando expira (2 minutos)

  Ele mantém um cache em ETS e agenda timers para expiração.
  """
  @behaviour TokenApp.TokenPoolBehaviour

  use GenServer
  require Logger
  alias TokenApp.Tokens

  # tempo máximo que um token pode ficar com um usuário (2 minutos)
  defp ttl_ms do
    Application.get_env(:token_app, __MODULE__)[:ttl_ms] || 120_000
  end

  defp sweep_interval_ms do
    Application.get_env(:token_app, __MODULE__)[:sweep_interval_ms] || 30_000
  end

  @table_active_by_token :token_pool_active_by_token
  @table_active_order :token_pool_active_order

  @doc """
  Aloca um token para `user_uuid`.

  Regra:
    - Se houver token disponível → usar esse.
    - Se não houver → pegar o ativo mais antigo e reatribuir.

  Retorna:
    {:ok, %{token_uuid, user_uuid, expires_in_ms}}
    {:error, reason}
  """
  def allocate(user_uuid, server \\ __MODULE__) do
    GenServer.call(server, {:allocate, user_uuid})
  end

  @doc """
  Libera TODOS os tokens.
  """
  def clear_all(server \\ __MODULE__) do
    GenServer.call(server, :clear_all)
  end

  @doc """
  Snapshot atual (debug/teste): ativos + disponíveis.
  """
  def snapshot() do
    GenServer.call(__MODULE__, :snapshot)
  end

  # -------------------------------------------------
  # Inicialização / Supervisor hook
  # -------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl true
  def init(_arg) do
    # Garante que as ETS com nomes fixos começam limpas
    ensure_fresh_table(@table_active_by_token, [:set, :public, :named_table])
    ensure_fresh_table(@table_active_order, [:ordered_set, :public, :named_table])

    # Carregar estado inicial do banco
    now_mono = System.monotonic_time(:millisecond)
    now_wall = DateTime.utc_now()

    %{active: active_rows, available: available_rows} = Tokens.snapshot_for_pool()

    # Registrar ativos em ETS e agendar timers
    for row <- active_rows do
      %{token_uuid: token_uuid, user_uuid: user_uuid, started_at: started_at} = row

      started_mono = calc_started_mono(started_at, now_wall, now_mono)

      remaining_ms =
        max(ttl_ms() - (now_mono - started_mono), 0)

      timer_ref =
        if remaining_ms == 0 do
          Process.send_after(self(), {:expire, token_uuid}, 0)
          :expired_immediately
        else
          Process.send_after(self(), {:expire, token_uuid}, remaining_ms)
        end

      put_active(token_uuid, %{
        user_uuid: user_uuid,
        started_at: started_at,
        started_mono: started_mono,
        timer_ref: timer_ref
      })
    end

    # Guardar disponíveis iniciais no estado do GenServer
    state = %{
      available: Map.new(available_rows, fn row -> {row.token_uuid, row} end)
    }

    # Agenda sweep periódico
    Process.send_after(self(), :sweep_expired, sweep_interval_ms())

    {:ok, state}
  end

  defp ensure_fresh_table(table_name, opts) do
    case :ets.whereis(table_name) do
      :undefined ->
        :ok

      tid when is_reference(tid) ->
        :ets.delete(table_name)
    end

    :ets.new(table_name, opts)
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    active_list = ets_active_list()
    available_list = Map.values(state.available)

    {:reply,
     %{
       active: active_list,
       available: available_list
     }, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    now = DateTime.utc_now()

    {:ok, %{released_count: released_count}} =
      Tokens.release_all_tokens(now)

    # limpar ETS
    for {token_uuid, data} <- ets_active_kv_list() do
      cancel_timer(data.timer_ref)
      :ets.delete(@table_active_by_token, token_uuid)
    end

    :ets.delete_all_objects(@table_active_order)

    # tudo volta a ser disponível
    new_available =
      Map.merge(
        state.available,
        Map.new(ets_active_kv_list(), fn {uuid, _} -> {uuid, %{token_uuid: uuid}} end)
      )

    {:reply, {:ok, %{released_count: released_count}}, %{state | available: new_available}}
  end

  @impl true
  def handle_call({:allocate, user_uuid}, _from, state) do
    now_wall = DateTime.utc_now()
    now_mono = System.monotonic_time(:millisecond)

    case pick_token_for_allocation(state) do
      {:available, %{token_uuid: token_uuid} = token_info, new_state} ->
        with {:ok, usage} <- assign_token(token_uuid, user_uuid, now_wall, now_mono) do
          {:reply,
           {:ok,
            %{
              token_uuid: token_uuid,
              user_uuid: user_uuid,
              expires_in_ms: ttl_ms()
            }}, new_state}
        else
          {:error, _} = err ->
            {:reply, err, state}
        end

      {:evict, %{token_uuid: token_uuid} = token_info, evicted_user_uuid, new_state} ->
        with {:ok, usage} <- reassign_token(token_uuid, user_uuid, now_wall, now_mono) do
          {:reply,
           {:ok,
            %{
              token_uuid: token_uuid,
              user_uuid: user_uuid,
              expires_in_ms: ttl_ms(),
              evicted_user: evicted_user_uuid
            }}, new_state}
        else
          {:error, _} = err ->
            {:reply, err, state}
        end

      :no_tokens ->
        {:reply, {:error, :no_tokens_defined}, state}
    end
  end

  @impl true
  def handle_info({:expire, token_uuid}, state) do
    # Libera token se ainda ativo e se o TTL já passou mesmo
    case :ets.lookup(@table_active_by_token, token_uuid) do
      [] ->
        {:noreply, state}

      [{^token_uuid, data}] ->
        now_mono = System.monotonic_time(:millisecond)

        if now_mono - data.started_mono >= ttl_ms() do
          # TTL passou; libera
          {:noreply, do_release(token_uuid, :expired, state)}
        else
          remaining = ttl_ms() - (now_mono - data.started_mono)
          new_timer = Process.send_after(self(), {:expire, token_uuid}, remaining)
          put_active(token_uuid, %{data | timer_ref: new_timer})
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:sweep_expired, state) do
    now_mono = System.monotonic_time(:millisecond)

    state_after_sweep =
      ets_active_kv_list()
      |> Enum.reduce(state, fn {token_uuid, data}, acc_state ->
        if now_mono - data.started_mono >= ttl_ms() do
          do_release(token_uuid, :expired, acc_state)
        else
          acc_state
        end
      end)

    # reagenda próximo sweep
    Process.send_after(self(), :sweep_expired, sweep_interval_ms())
    {:noreply, state_after_sweep}
  end

  # -------------------------------------------------
  # Funções internas principais
  # -------------------------------------------------

  # escolhe token pra alocar:
  # - se tem disponível → pega um e remove de available
  # - senão → pega mais antigo ativo
  defp pick_token_for_allocation(state) do
    case Map.values(state.available) do
      [one | rest] ->
        new_available = Map.drop(state.available, [one.token_uuid])
        {:available, one, %{state | available: new_available}}

      [] ->
        # não tem disponível
        case oldest_active() do
          nil ->
            :no_tokens

          %{token_uuid: token_uuid, user_uuid: old_user_uuid} = active_info ->
            {:evict, %{token_uuid: token_uuid}, old_user_uuid, state}
        end
    end
  end

  # atribui um token que estava disponível
  defp assign_token(token_uuid, user_uuid, now_wall, now_mono) do
    case Tokens.get_token_by_uuid(token_uuid) do
      nil ->
        {:error, :token_not_found}

      %{id: token_id} ->
        case Tokens.reassign_token_to_user(token_id, user_uuid, now_wall) do
          {:ok, %{open_new: usage}} ->
            timer_ref = Process.send_after(self(), {:expire, token_uuid}, ttl_ms())

            put_active(token_uuid, %{
              user_uuid: user_uuid,
              started_at: now_wall,
              started_mono: now_mono,
              timer_ref: timer_ref
            })

            {:ok, usage}

          {:error, _step, reason, _changes_so_far} ->
            {:error, reason}
        end
    end
  end

  # reatribui um token que já estava ativo em outra pessoa
  defp reassign_token(token_uuid, new_user_uuid, now_wall, now_mono) do
    case Tokens.get_token_by_uuid(token_uuid) do
      nil ->
        {:error, :token_not_found}

      %{id: token_id} ->
        case Tokens.reassign_token_to_user(token_id, new_user_uuid, now_wall) do
          {:ok, %{open_new: usage}} ->
            timer_ref = Process.send_after(self(), {:expire, token_uuid}, ttl_ms())

            put_active(token_uuid, %{
              user_uuid: new_user_uuid,
              started_at: now_wall,
              started_mono: now_mono,
              timer_ref: timer_ref
            })

            {:ok, usage}

          {:error, _step, reason, _changes_so_far} ->
            {:error, reason}
        end
    end
  end

  # Libera token
  # 1. fecha uso aberto no banco
  # 2. remove token da ETS de ativos
  # 3. adiciona token de volta no map de disponíveis
  defp do_release(token_uuid, reason, state) do
    Logger.debug("Releasing token #{token_uuid} reason=#{inspect(reason)}")

    case :ets.lookup(@table_active_by_token, token_uuid) do
      [] ->
        state

      [{^token_uuid, data}] ->
        cancel_timer(data.timer_ref)

        token = Tokens.get_token_by_uuid(token_uuid)

        if token do
          {:ok, _} = Tokens.release_token(token.id, DateTime.utc_now())
        end

        :ets.delete(@table_active_by_token, token_uuid)
        delete_from_order(data.started_mono, token_uuid)

        new_available =
          Map.put(state.available, token_uuid, %{
            token_uuid: token_uuid
          })

        %{state | available: new_available}
    end
  end

  # -------------------------------------------------
  # Helpers p/ ETS e ordenação
  # -------------------------------------------------

  defp put_active(token_uuid, %{started_mono: started_mono} = data) do
    :ets.insert(@table_active_by_token, {token_uuid, data})
    :ets.insert(@table_active_order, {started_mono, token_uuid})
    :ok
  end

  defp oldest_active() do
    case :ets.first(@table_active_order) do
      :"$end_of_table" ->
        nil

      first_key ->
        [{^first_key, token_uuid}] = :ets.lookup(@table_active_order, first_key)
        [{^token_uuid, data}] = :ets.lookup(@table_active_by_token, token_uuid)

        %{
          token_uuid: token_uuid,
          user_uuid: data.user_uuid,
          started_mono: data.started_mono,
          started_at: data.started_at
        }
    end
  end

  defp delete_from_order(started_mono, token_uuid) do
    # Remove entrada correspondente da tabela ordenada
    :ets.delete(@table_active_order, started_mono)
    # também garantir que não tenha lixo duplicado
    :ets.delete(@table_active_by_token, token_uuid)
    :ok
  end

  defp ets_active_kv_list() do
    :ets.tab2list(@table_active_by_token)
  end

  defp ets_active_list() do
    Enum.map(ets_active_kv_list(), fn {token_uuid, data} ->
      %{
        token_uuid: token_uuid,
        user_uuid: data.user_uuid,
        started_at: data.started_at
      }
    end)
  end

  defp cancel_timer(:expired_immediately), do: :ok
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  # "started_mono" consistente após restart.
  #  - no banco, temos started_at.
  #  - ao subir app, pegamos now_wall (UTC agora) e now_mono (monotonic agora).
  #  - estimamos started_mono = now_mono - (now_wall - started_at em ms).
  defp calc_started_mono(started_at, now_wall, now_mono) do
    diff_ms =
      DateTime.diff(now_wall, started_at, :millisecond)

    now_mono - diff_ms
  end
end
