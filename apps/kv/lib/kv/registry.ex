defmodule KV.Registry do
  use GenServer

  # In practice, if you find yourself in a position where you need a registry for dynamic processes, you should use the Registry module provided as part of Elixir. It provides functionality similar to the one we have built using a GenServer + :ets while also being able to perform both writes and reads concurrently. It has been benchmarked to scale across all cores even on machines with 40 cores.




    ## Client API

  @doc """
  Starts the registry with the given options.

  `:name` is always required.
  """
  def start_link(opts) do
    # 1. Pass the name to GenServer's init
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end


  @doc """
  Looks up the bucket pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, name) do
    # 2. Lookup is now done directly in ETS, without accessing the server
    case :ets.lookup(server, name) do
      [{^name, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Ensures there is a bucket associated with the given `name` in `server`.
  """
  def create(server, name) do
    GenServer.call(server, {:create, name})
  end







  ## Server callbacks

  @impl true
  def init(table) do
    # 3. We have replaced the names map by the ETS table
    names = :ets.new(table, [:named_table, read_concurrency: true])
    refs  = %{}
    {:ok, {names, refs}}
  end

  # 4. The previous handle_call callback for lookup was removed


  @impl true
  def handle_call({:create, name}, _from, {names, refs}) do
    # 5. Read and write to the ETS table instead of the map
    case lookup(names, name) do
      {:ok, bucket_pid} ->
        {:reply, bucket_pid, {names, refs}}

      :error ->
        {:ok, bucket_pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, KV.Bucket)
        ref = Process.monitor(bucket_pid)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, bucket_pid})
        {:reply, bucket_pid, {names, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    # 6. Delete from the ETS table instead of the map
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unexpected message in KV.Registry: #{inspect(msg)}")
    {:noreply, state}
  end

  # @impl true
  # def handle_info(_msg, state) do
  #   {:noreply, state}
  # end
end

# Links are bi-directional.
# If you link two processes and one of them crashes, the other side will crash too
# (unless it is trapping exits). A monitor is uni-directional: only the monitoring process will receive
#  notifications about the monitored one. In other words: use links when you want linked crashes,
#  and monitors when you just want to be informed of crashes, exits, and so on.
