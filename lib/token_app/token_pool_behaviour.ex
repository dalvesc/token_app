defmodule TokenApp.TokenPoolBehaviour do
  @moduledoc """
  Comportamento para permitir que controllers falem com um processo de pool
  (normal ou isolado em teste) sem depender diretamente do nome global.
  """

  @callback allocate(binary()) ::
              {:ok,
               %{
                 token_uuid: binary(),
                 user_uuid: binary(),
                 expires_in_ms: integer(),
                 evicted_user: binary() | nil
               }}
              | {:error, any()}

  @callback clear_all() ::
              {:ok, %{released_count: non_neg_integer()}}
              | {:error, any()}
end
