defmodule TokenApp.Tokens do
  @moduledoc """
  Contexto de domínio para gerenciamento de tokens e histórico de uso.

  Responsabilidades:
  - Saber quais tokens existem.
  - Saber quais tokens estão atualmente ativos (em uso).
  - Criar / encerrar usos (token_usages).
  - Consultas para API (listar estado, histórico).
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias TokenApp.Repo

  alias TokenApp.Tokens.{Token, TokenUsage}

  @doc """
  Retorna todos os tokens cadastrados.
  """
  def list_all_tokens() do
    Repo.all(Token)
  end

  @doc """
  Retorna token pelo UUID público.
  """
  def get_token_by_uuid!(uuid) do
    Repo.get_by!(Token, uuid: uuid)
  end

  @doc """
  Retorna token pelo UUID público, ou nil.
  """
  def get_token_by_uuid(uuid) do
    Repo.get_by(Token, uuid: uuid)
  end

  @doc """
  Retorna o uso aberto atual (se existir) de um token específico.
  Uso aberto = um registro em token_usages com released_at == nil.
  """
  def get_open_usage_for_token(token_id) do
    Repo.one(
      from u in TokenUsage,
        where: u.token_id == ^token_id and is_nil(u.released_at),
        limit: 1
    )
  end

  @doc """
  Lista todos os usos abertos de todos os tokens.

  Retorna uma lista de `%{token_uuid, user_uuid, started_at, token_id, usage_id}`.
  """
  def list_all_open_usages() do
    Repo.all(
      from u in TokenUsage,
        join: t in Token,
        on: t.id == u.token_id,
        where: is_nil(u.released_at),
        select: %{
          token_id: t.id,
          token_uuid: t.uuid,
          user_uuid: u.user_uuid,
          started_at: u.started_at,
          usage_id: u.id
        }
    )
  end

  @doc """
  Lista histórico completo de um token (todas as alocações passadas).
  Ordena do mais recente pro mais antigo.
  """
  def list_usage_history_for_token(token_uuid) do
    query =
      from u in TokenUsage,
        join: t in Token,
        on: t.id == u.token_id,
        where: t.uuid == ^token_uuid,
        order_by: [desc: u.started_at],
        select: %{
          user_uuid: u.user_uuid,
          started_at: u.started_at,
          released_at: u.released_at
        }

    Repo.all(query)
  end

  @doc """
  Retorna dois conjuntos:
    - ativos: lista de %{token_uuid, user_uuid, started_at}
    - disponíveis: lista só com token_uuid
  """
  def list_current_state() do
    # ativos
    active =
      Repo.all(
        from u in TokenUsage,
          join: t in Token,
          on: t.id == u.token_id,
          where: is_nil(u.released_at),
          select: %{
            token_uuid: t.uuid,
            user_uuid: u.user_uuid,
            started_at: u.started_at
          }
      )

    # todos os tokens
    all_tokens =
      Repo.all(
        from t in Token,
          select: t.uuid
      )

    active_set = MapSet.new(Enum.map(active, & &1.token_uuid))

    available =
      all_tokens
      |> Enum.reject(&MapSet.member?(active_set, &1))
      |> Enum.map(&%{token_uuid: &1})

    %{active: active, available: available}
  end

  @doc """
  Fecha (marca released_at) o uso aberto de um token, se existir.
  Retorna {:ok, %{usage: usage_before_close}}.
  Se não tinha uso aberto, retorna {:ok, %{usage: nil}}.
  """
  def multi_close_open_usage(multi, step_name, token_id, now) do
    Multi.run(multi, step_name, fn repo, _changes_so_far ->
      open_usage =
        repo.one(
          from u in TokenUsage,
            where: u.token_id == ^token_id and is_nil(u.released_at),
            limit: 1
        )

      if open_usage do
        changeset =
          Ecto.Changeset.change(open_usage,
            released_at: now
          )

        case repo.update(changeset) do
          {:ok, updated} ->
            {:ok, %{usage: updated}}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:ok, %{usage: nil}}
      end
    end)
  end

  @doc """
  Abre um novo uso para (token_id, user_uuid).
  Retorna {:ok, usage}.
  """
  def multi_open_new_usage(multi, step_name, token_id, user_uuid, now) do
    Multi.run(multi, step_name, fn repo, _changes_so_far ->
      usage_changeset =
        TokenUsage.changeset(%TokenUsage{}, %{
          token_id: token_id,
          user_uuid: user_uuid,
          started_at: now,
          released_at: nil
        })

      repo.insert(usage_changeset)
    end)
  end

  @doc """
  Transação completa para:
    1. Fechar uso antigo (se existir).
    2. Criar novo uso para novo user.

  Retorna {:ok, %{close_old: ..., open_new: usage}}.
  """
  def reassign_token_to_user(token_id, user_uuid, now \\ DateTime.utc_now()) do
    Multi.new()
    |> multi_close_open_usage(:close_old, token_id, now)
    |> multi_open_new_usage(:open_new, token_id, user_uuid, now)
    |> Repo.transaction()
  end

  @doc """
  Libera um token sem reatribuir para outro usuário:
  - só fecha o uso aberto atual.
  """
  def release_token(token_id, now \\ DateTime.utc_now()) do
    Multi.new()
    |> multi_close_open_usage(:close_old, token_id, now)
    |> Repo.transaction()
  end

  @doc """
  Libera todos os tokens atualmente ativos:
  retorna {:ok, %{released_count: n}}.
  """
  def release_all_tokens(now \\ DateTime.utc_now()) do
    {count, _} =
      Repo.update_all(
        from(u in TokenUsage, where: is_nil(u.released_at)),
        set: [released_at: now]
      )

    {:ok, %{released_count: count}}
  end

  @doc """
  Retorna {ativos, disponiveis} para o TokenPool:
  - ativos: [%{token_id, token_uuid, user_uuid, started_at}]
  - disponiveis: [%{token_id, token_uuid}]
  """
  def snapshot_for_pool() do
    active_rows =
      Repo.all(
        from u in TokenUsage,
          join: t in Token,
          on: t.id == u.token_id,
          where: is_nil(u.released_at),
          select: %{
            token_id: t.id,
            token_uuid: t.uuid,
            user_uuid: u.user_uuid,
            started_at: u.started_at
          }
      )

    all_rows =
      Repo.all(
        from t in Token,
          select: %{
            token_id: t.id,
            token_uuid: t.uuid
          }
      )

    active_ids = MapSet.new(Enum.map(active_rows, & &1.token_id))

    available_rows =
      Enum.reject(all_rows, fn %{token_id: id} ->
        MapSet.member?(active_ids, id)
      end)

    %{active: active_rows, available: available_rows}
  end
end
