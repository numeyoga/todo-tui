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
    "a" => TodoTxt.Commands.Add
  }

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

    case rest do
      [cmd | args] ->
        case @commands[cmd] do
          nil ->
            {:usage, "unknown command #{cmd} (try: todo help)"}

          mod ->
            with {:ok, tasks} <- Store.read(env.paths.todo),
                 {:ok, done} <- Store.read(env.paths.done) do
              mod.run(args, Map.merge(env, %{tasks: tasks, done_tasks: done}))
            end
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
