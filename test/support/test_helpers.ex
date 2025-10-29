defmodule TokenApp.TestHelpers do
  @moduledoc false

  @doc """
  Executa `fun` repetidamente até retornar truthy ou até estourar o timeout.

  - fun: função zero-arity () -> truthy / falsy
  - timeout_ms: tempo máximo total em ms (default 1000)
  - step_ms: intervalo entre tentativas em ms (default 50)

  Se a condição não virar verdade até o timeout, levanta um erro.
  """
  def wait_until(fun, timeout_ms \\ 1_000, step_ms \\ 50) when is_function(fun, 0) do
    start_ms = System.monotonic_time(:millisecond)
    do_wait_until(fun, start_ms, timeout_ms, step_ms)
  end

  defp do_wait_until(fun, start_ms, timeout_ms, step_ms) do
    if fun.() do
      :ok
    else
      now_ms = System.monotonic_time(:millisecond)

      if now_ms - start_ms > timeout_ms do
        raise "condition did not become true within #{timeout_ms}ms"
      else
        Process.sleep(step_ms)
        do_wait_until(fun, start_ms, timeout_ms, step_ms)
      end
    end
  end
end
