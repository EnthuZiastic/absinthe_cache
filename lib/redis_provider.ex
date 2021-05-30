defmodule AbsintheCache.RedisProvider do
  # TODO: Check if con_cache is available
  @behaviour AbsintheCache.Behaviour

  @compile :inline_list_funcs
  @compile {:inline, get: 2, store: 3, get_or_store: 4, cache_item: 3}

  @max_cache_ttl 30 * 60

  @impl true
  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl true
  def clear_all(cache) do
    cache
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(cache, key) end)
  end

  @impl true
  def get(_, {key, _}) do
    {:ok, conn} = Redix.start_link(System.get_env("REDIS_URL", "redis://127.0.0.1:6379"))

    case Redix.command(conn, ["GET", key]) |> IO.inspect() do
      {:ok, value} ->
        value

      _ ->
        nil
    end
  end

  @impl true
  def store(cache, {key, _}, value) do
    case value do
      {:error, _} ->
        :ok

      {:nocache, _} ->
        Process.put(:has_nocache_field, true)
        :ok

      value ->
        cache_item(cache, key, {:stored, value})
    end
  end

  @impl true
  def get_or_store(cache, {key, _}, func, cache_modify_middleware) do
    IO.puts("IN GET OR STORE")
    IO.inspect(cache)
    IO.inspect(key)
    {:ok, conn} = Redix.start_link(System.get_env("REDIS_URL", "redis://127.0.0.1:6379"))

    {result, error_if_any} =
      case Redix.command(conn, ["GET", key]) |> IO.inspect() do
        {:ok, value} when value != nil ->
          IO.puts("VALUE HAI")
          IO.inspect(VALUE)
          value = Jason.decode!(value)
          {{:ok, value}, nil}

        _ ->
          case func.() |> IO.inspect() do
            {:error, _} = error ->
              {nil, error}

            {:middleware, _, _} = tuple ->
              # Decides on its behalf whether or not to put the value in the cache
              {cache_modify_middleware.(cache, key, tuple), nil}

            {:nocache, {:ok, _result} = value} ->
              Process.put(:do_not_cache_query, true)
              {value, nil}

            {:ok, value} ->
              IO.puts("VALUE HAI, CACHE ADD KAROu")
              cache_item(cache, key, Jason.encode!(value)) |> IO.inspect()
              {{:ok, value}, nil}
          end
      end

    IO.puts("IN END")
    IO.inspect(result)
    IO.inspect(error_if_any)

    if error_if_any != nil do
      # Logger.warn("Somethting went wrong...")
      error_if_any
    else
      result
    end
  end

  defp cache_item(_, {_, ttl} = key, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    IO.puts("IN CACHE ITEM 1")
    IO.inspect(key)
    IO.inspect(value)
    {:ok, conn} = Redix.start_link(System.get_env("REDIS_URL", "redis://127.0.0.1:6379"))
    Redix.command(conn, ["SET", key, value])
  end

  defp cache_item(_, key, value) do
    IO.puts("IN CACHE ITEM")
    IO.inspect(key)
    IO.inspect(value)
    {:ok, conn} = Redix.start_link(System.get_env("REDIS_URL", "redis://127.0.0.1:6379"))
    Redix.command(conn, ["SET", key, value])
  end
end
