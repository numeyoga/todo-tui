defmodule TodoTxt.Tui.ResizeDebouncer do
  @moduledoc """
  Filtre et temporise les notifications de redimensionnement du terminal
  entre `TermUI.Terminal` et `TermUI.Runtime`.

  Lors d'un redimensionnement rapide à la souris, le système d'exploitation
  émet de nombreux signaux SIGWINCH par seconde. Sans temporisation,
  chaque signal entraîne une réallocation de tampons et un redessin complet
  dans TermUI.Runtime, provoquant le rejeu séquentiel de toutes les tailles
  intermédiaires.

  Ce GenServer intercepte les messages `{:terminal_resize, {rows, cols}}` émis
  par `TermUI.Terminal` et ne transmet que la dernière taille au processus Runtime
  une fois le mouvement stabilisé (après un délai configurable de `debounce_ms`).
  """

  use GenServer

  @default_debounce_ms 50

  @type size :: {pos_integer(), pos_integer()}

  @type state :: %{
          runtime: pid(),
          debounce_ms: non_neg_integer(),
          timer: reference() | nil,
          latest: size() | nil,
          last_sent: size() | nil
        }

  @doc """
  Démarre le GenServer de debouncing pour le processus Runtime spécifié.
  """
  @spec start(pid(), keyword()) :: GenServer.on_start()
  def start(runtime_pid, opts \\ []) do
    GenServer.start(__MODULE__, {runtime_pid, opts, self()})
  end

  @doc """
  Démarre et lie le GenServer de debouncing.
  """
  @spec start_link(pid(), keyword()) :: GenServer.on_start()
  def start_link(runtime_pid, opts \\ []) do
    GenServer.start_link(__MODULE__, {runtime_pid, opts, self()})
  end

  @impl GenServer
  def init({runtime_pid, opts, runner_pid}) do
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)

    if Process.whereis(TermUI.Terminal) do
      TermUI.Terminal.unregister_resize_callback(runtime_pid)
      TermUI.Terminal.register_resize_callback(self())
    end

    Process.monitor(runtime_pid)
    if runner_pid != runtime_pid, do: Process.monitor(runner_pid)

    initial_size =
      if Process.whereis(TermUI.Terminal) do
        case TermUI.Terminal.get_terminal_size() do
          {:ok, size} -> size
          _ -> nil
        end
      end

    {:ok,
     %{
       runtime: runtime_pid,
       debounce_ms: debounce_ms,
       timer: nil,
       latest: nil,
       last_sent: initial_size
     }}
  end

  @impl GenServer
  def handle_info({:terminal_resize, size}, state) do
    latest_size = drain_terminal_resize(size)

    if state.timer do
      Process.cancel_timer(state.timer)
    end

    timer = Process.send_after(self(), :flush, state.debounce_ms)
    {:noreply, %{state | latest: latest_size, timer: timer}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    state =
      if state.latest != nil and state.latest != state.last_sent and
           Process.alive?(state.runtime) do
        send(state.runtime, {:terminal_resize, state.latest})
        %{state | last_sent: state.latest, timer: nil}
      else
        %{state | timer: nil}
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    cleanup_terminal()
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    cleanup_terminal()
    :ok
  end

  defp cleanup_terminal do
    if Process.whereis(TermUI.Terminal) do
      TermUI.Terminal.unregister_resize_callback(self())
    end
  end

  defp drain_terminal_resize(latest) do
    receive do
      {:terminal_resize, size} ->
        drain_terminal_resize(size)
    after
      0 ->
        latest
    end
  end
end
