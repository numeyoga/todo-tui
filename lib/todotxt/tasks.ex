defmodule TodoTxt.Tasks do
  @moduledoc """
  Imperative facade: `TodoTxt.Ops` (pure) + persistence, shared by the
  CLI (`TodoTxt.Commands.*`) and the TUI effect interpreter.

  Every function takes an injectable `io` map (`%{read:, write:, append:}`,
  extra keys ignored) as first argument, defaulting to `default_io/0`
  (`TodoTxt.Store`). Results are neutral data — callers format their own
  output/status:

      {:ok, %{tasks: [...], ...}} | {:error, msg}
  """

  alias TodoTxt.{Ops, Store, Task}

  @type io :: %{
          required(:read) => (Path.t() -> {:ok, [Task.t()]} | {:error, String.t()}),
          required(:write) => (Path.t(), [Task.t()] -> :ok | {:error, String.t()}),
          required(:append) => (Path.t(), [Task.t()] -> :ok | {:error, String.t()}),
          optional(atom()) => term()
        }
  @type paths :: %{
          required(:todo) => Path.t(),
          required(:done) => Path.t(),
          optional(atom()) => term()
        }
  @type result(m) :: {:ok, m} | {:error, String.t()}

  @spec default_io() :: io()
  def default_io, do: %{read: &Store.read/1, write: &Store.write/2, append: &Store.append/2}

  @doc "Read todo.txt and done.txt."
  @spec load(io(), paths()) :: result(%{tasks: [Task.t()], done_tasks: [Task.t()]})
  def load(io \\ default_io(), paths) do
    with {:ok, tasks} <- io.read.(paths.todo),
         {:ok, done} <- io.read.(paths.done) do
      {:ok, %{tasks: tasks, done_tasks: done}}
    end
  end

  @doc """
  Complete `t` today and rewrite todo.txt. A recurrence is numbered
  `Ops.next_line(tasks)` and lands at the end of the same write (same
  bytes as write + append, but a single atomic replace).
  """
  @spec complete(io(), paths(), [Task.t()], Task.t(), Date.t()) ::
          result(%{tasks: [Task.t()], task: Task.t(), recur: Task.t() | nil})
  def complete(io \\ default_io(), paths, tasks, t, today) do
    with {:ok, ts, recur} <- Ops.complete(tasks, t, today) do
      recur = recur && %{recur | line: Ops.next_line(tasks)}
      ts = if recur, do: ts ++ [recur], else: ts

      with :ok <- io.write.(paths.todo, ts) do
        done = Enum.find(ts, &(&1.line == t.line))
        {:ok, %{tasks: ts, task: done, recur: recur}}
      end
    end
  end

  @doc "Reopen a done task of todo.txt in place."
  @spec uncomplete(io(), paths(), [Task.t()], Task.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def uncomplete(io \\ default_io(), paths, tasks, t),
    do: persist_task(io, paths.todo, Ops.uncomplete(tasks, t), t.line)

  @doc """
  Reopen a task of done.txt: append it (uncompleted) to todo.txt, then
  rewrite done.txt without it — same order and guarantees as `move/5`.
  """
  @spec reopen(io(), paths(), [Task.t()], Task.t()) ::
          result(%{done_tasks: [Task.t()], task: Task.t()})
  def reopen(io \\ default_io(), paths, done_tasks, t) do
    reopened = Task.uncomplete(t)

    with {:ok, %{tasks: done2}} <- move(io, paths.done, paths.todo, done_tasks, reopened) do
      {:ok, %{done_tasks: done2, task: reopened}}
    end
  end

  @doc """
  Move `t` from `src_path` (whose list is `tasks`) to the end of
  `dest_path`. Appends first: a failure leaves a duplicate, never a loss.
  """
  @spec move(io(), Path.t(), Path.t(), [Task.t()], Task.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def move(io \\ default_io(), src_path, dest_path, tasks, t) do
    with :ok <- io.append.(dest_path, [t]),
         {:ok, ts} <- Ops.delete(tasks, t),
         :ok <- io.write.(src_path, ts) do
      {:ok, %{tasks: ts, task: t}}
    end
  end

  @doc "Append done tasks to done.txt (skipped when none), rewrite todo.txt with the open ones."
  @spec archive(io(), paths(), [Task.t()]) ::
          result(%{tasks: [Task.t()], archived: [Task.t()], count: non_neg_integer()})
  def archive(io \\ default_io(), paths, tasks) do
    {open, done} = Ops.archive(tasks)

    with :ok <- if(done == [], do: :ok, else: io.append.(paths.done, done)),
         :ok <- io.write.(paths.todo, open) do
      {:ok, %{tasks: open, archived: done, count: length(done)}}
    end
  end

  @doc "Append a new task (`Ops.add/3`) to todo.txt."
  @spec add(io(), paths(), [Task.t()], String.t(), Date.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def add(io \\ default_io(), paths, tasks, text, today) do
    task = Ops.add(tasks, text, today)

    with :ok <- io.append.(paths.todo, [task]) do
      {:ok, %{tasks: tasks ++ [task], task: task}}
    end
  end

  # --- Single-list mutations: `path` is the file `tasks` was read from. ---

  @spec set_priority(io(), Path.t(), [Task.t()], Task.t(), non_neg_integer() | nil) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def set_priority(io \\ default_io(), path, tasks, t, prio),
    do: persist_task(io, path, Ops.set_priority(tasks, t, prio), t.line)

  @spec replace_text(io(), Path.t(), [Task.t()], Task.t(), String.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def replace_text(io \\ default_io(), path, tasks, t, text),
    do: persist_task(io, path, Ops.replace_text(tasks, t, text), t.line)

  @spec append_text(io(), Path.t(), [Task.t()], Task.t(), String.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def append_text(io \\ default_io(), path, tasks, t, text),
    do: persist_task(io, path, Ops.append_text(tasks, t, text), t.line)

  @spec prepend_text(io(), Path.t(), [Task.t()], Task.t(), String.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def prepend_text(io \\ default_io(), path, tasks, t, text),
    do: persist_task(io, path, Ops.prepend_text(tasks, t, text), t.line)

  @doc "Remove `t`; `task` in the result is the deleted task."
  @spec delete(io(), Path.t(), [Task.t()], Task.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def delete(io \\ default_io(), path, tasks, t) do
    with {:ok, %{tasks: ts}} <- persist(io, path, Ops.delete(tasks, t)) do
      {:ok, %{tasks: ts, task: t}}
    end
  end

  @spec delete_term(io(), Path.t(), [Task.t()], Task.t(), String.t()) ::
          result(%{tasks: [Task.t()], task: Task.t()})
  def delete_term(io \\ default_io(), path, tasks, t, term),
    do: persist_task(io, path, Ops.delete_term(tasks, t, term), t.line)

  @spec dedupe(io(), Path.t(), [Task.t()]) ::
          result(%{tasks: [Task.t()], removed: non_neg_integer()})
  def dedupe(io \\ default_io(), path, tasks) do
    uniq = Ops.dedupe(tasks)

    with {:ok, %{tasks: ts}} <- persist(io, path, {:ok, uniq}) do
      {:ok, %{tasks: ts, removed: length(tasks) - length(ts)}}
    end
  end

  @doc "Rewrite `path` with an `Ops` result; errors pass through without writing."
  @spec persist(io(), Path.t(), {:ok, [Task.t()]} | {:error, String.t()}) ::
          result(%{tasks: [Task.t()]})
  def persist(io \\ default_io(), path, op_result)

  def persist(io, path, {:ok, ts}) do
    with :ok <- io.write.(path, ts), do: {:ok, %{tasks: ts}}
  end

  def persist(_io, _path, {:error, _} = e), do: e

  defp persist_task(io, path, op_result, line) do
    with {:ok, %{tasks: ts}} <- persist(io, path, op_result) do
      {:ok, %{tasks: ts, task: Enum.find(ts, &(&1.line == line))}}
    end
  end
end
