defmodule TodoTxt.Tui do
  @moduledoc "Interactive TUI — `todo --tui`. Elm app on term_ui."
  use TermUI.Elm

  alias TermUI.Command

  @doc "Runs the TUI; loops for external $EDITOR sessions. Returns {:ok, nil} | {:error, msg}."
  def run(env) do
    env =
      env
      |> Map.put_new(:today, Date.utc_today())
      |> Map.put_new(:io, %{
        read: &TodoTxt.Store.read/1,
        write: &TodoTxt.Store.write/2,
        append: &TodoTxt.Store.append/2,
        stat: &File.stat/1
      })
      |> Map.put(:caller, self())

    # TermUI.Runtime.run/1 returns :ok | {:error, term}; the test seam may
    # also return {:ok, _} (TermUI.App.run/2's shape) — both mean clean exit.
    runner = env[:runner] || fn e -> TermUI.Runtime.run(root: __MODULE__, env: e) end

    case runner.(env) do
      :ok -> handle_exit(env)
      {:ok, _} -> handle_exit(env)
      {:error, m} -> {:error, m}
    end
  end

  defp handle_exit(env) do
    # Selective receive: only consume the TUI's own edit-request message;
    # unrelated mailbox messages must be left for the caller.
    receive do
      {:tui_exit, :edit} ->
        case edit_external(env) do
          :ok -> run(env)
          {:error, m} -> {:error, m}
        end
    after
      0 -> {:ok, nil}
    end
  end

  defp edit_external(env) do
    editor = System.get_env("EDITOR")

    if is_nil(editor) do
      {:error, "$EDITOR not set"}
    else
      try do
        case System.cmd(editor, [env.paths.todo], into: IO.stream(:stdio, :line)) do
          {_, 0} -> :ok
          {_, code} -> {:error, "editor exited #{code}"}
        end
      rescue
        ErlangError -> {:error, "editor not found: #{editor}"}
      end
    end
  end

  # --- Elm callbacks (T5+ complète ; squelette autonome, sans State) ---
  def init(opts) do
    env = Keyword.fetch!(opts, :env)
    {:ok, %{env: env}, [Command.interval(2_000, :tick)]}
  end

  def event_to_msg(_, _), do: :ignore
  def update(_, state), do: {state, []}
  def view(_), do: text("todo --tui")
  def handle_info(msg, state), do: update(msg, state)
end
