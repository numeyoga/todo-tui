defmodule TodoTxt.CLI do
  @moduledoc """
  Entry point of the `todo` escript.

  `main/1` resolves the real environment (paths via `TodoTxt.Config`,
  `today` via `Date.utc_today/0`), prints and halts — it is the only
  place allowed to call `System.halt/1`.

  `run/2` is pure dispatch for tests: it takes `argv` and an injected
  `env` (`%{paths: ..., today: ...}`) and returns
  `{:ok, msg | nil} | {:error, msg} | {:usage, msg}`.

  Command contract:

      Mod.run(args :: [String.t()], ctx) ::
        {:ok, msg} | {:error, msg} | {:usage, msg}

  where `ctx` is `%{paths:, tasks:, done_tasks:, today:, opts:}` and
  `opts` is `%{file:, done_file:, plain: bool, json: bool}`.
  """

  alias TodoTxt.{Config, Store}

  @commands %{
    "add" => TodoTxt.Commands.Add,
    "a" => TodoTxt.Commands.Add,
    "do" => TodoTxt.Commands.Do,
    "undo" => TodoTxt.Commands.Undo,
    "del" => TodoTxt.Commands.Del,
    "rm" => TodoTxt.Commands.Del,
    "ls" => TodoTxt.Commands.List,
    "list" => TodoTxt.Commands.List,
    "pri" => TodoTxt.Commands.Pri,
    "depri" => TodoTxt.Commands.Depri,
    "append" => TodoTxt.Commands.Append,
    "app" => TodoTxt.Commands.Append,
    "prepend" => TodoTxt.Commands.Prepend,
    "prep" => TodoTxt.Commands.Prepend,
    "replace" => TodoTxt.Commands.Replace,
    "move" => TodoTxt.Commands.Move,
    "mv" => TodoTxt.Commands.Move,
    "listall" => TodoTxt.Commands.ListAll,
    "lsa" => TodoTxt.Commands.ListAll,
    "listproj" => {TodoTxt.Commands.ListMeta, "proj"},
    "lsprj" => {TodoTxt.Commands.ListMeta, "proj"},
    "listcon" => {TodoTxt.Commands.ListMeta, "con"},
    "lsc" => {TodoTxt.Commands.ListMeta, "con"},
    "listpri" => {TodoTxt.Commands.ListMeta, "pri"},
    "lspr" => {TodoTxt.Commands.ListMeta, "pri"},
    "due" => TodoTxt.Commands.Due,
    "agenda" => TodoTxt.Commands.Agenda,
    "archive" => TodoTxt.Commands.Archive,
    "dedupe" => TodoTxt.Commands.Dedupe,
    "report" => TodoTxt.Commands.Report,
    "edit" => TodoTxt.Commands.Edit,
    "help" => TodoTxt.Commands.Help,
    "listaddons" => TodoTxt.Commands.ListAddons
  }

  @version "todo 0.1.0"

  def main(argv) do
    env = %{today: Date.utc_today()}

    case run(argv, env) do
      {:ok, out} ->
        if(out, do: IO.puts(out))
        System.halt(0)

      {:error, m} ->
        IO.puts(:stderr, "todo: " <> m)
        System.halt(1)

      {:usage, m} ->
        IO.puts(:stderr, "usage: " <> m)
        System.halt(2)
    end
  end

  def run(argv, env) do
    {opts, rest} = parse_global(argv, %{file: nil, done_file: nil, plain: false, json: false})
    env = env |> Map.put_new(:paths, Config.resolve_paths(opts)) |> Map.put(:opts, opts)

    dispatch = fn mod, args ->
      with {:ok, tasks} <- Store.read(env.paths.todo),
           {:ok, done} <- Store.read(env.paths.done) do
        mod.run(args, Map.merge(env, %{tasks: tasks, done_tasks: done}))
      end
    end

    case rest do
      ["--version" | _] ->
        {:ok, @version}

      ["-h" | _] ->
        {:ok, TodoTxt.Commands.Help.text()}

      [cmd | args] ->
        case @commands[cmd] do
          nil -> {:usage, "unknown command #{cmd} (try: todo help)"}
          {mod, sub} -> dispatch.(mod, [sub | args])
          mod -> dispatch.(mod, args)
        end

      [] ->
        {:usage, "no command (try: todo help)"}
    end
  end

  defp parse_global(argv, opts) do
    case argv do
      ["-f", v | r] -> parse_global(r, %{opts | file: v})
      ["--file", v | r] -> parse_global(r, %{opts | file: v})
      ["-d", v | r] -> parse_global(r, %{opts | done_file: v})
      ["--done-file", v | r] -> parse_global(r, %{opts | done_file: v})
      ["--plain" | r] -> parse_global(r, %{opts | plain: true})
      ["--json" | r] -> parse_global(r, %{opts | json: true})
      _ -> {opts, argv}
    end
  end
end
