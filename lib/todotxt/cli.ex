defmodule TodoTxt.CLI do
  @moduledoc """
  Entry point of the `todo` escript.

  `main/1` resolves the real environment (paths via `TodoTxt.Config`,
  `today` via `Date.utc_today/0`), prints and halts — it is the only
  place allowed to call `System.halt/1`.

  `run/2` is pure dispatch for tests: it takes `argv` and an injected
  `env` (`%{paths: ..., today: ...}`, optionally `config:` to bypass
  the config file) and returns
  `{:ok, msg | nil} | {:error, msg} | {:usage, msg}`.

  Command contract:

      Mod.run(args :: [String.t()], ctx) ::
        {:ok, msg} | {:error, msg} | {:usage, msg}

  where `ctx` is `%{paths:, tasks:, done_tasks:, today:, opts:}` and
  `opts` is `%{file:, done_file:, plain: bool, json: bool, sort: nil | "line"}`.
  """

  alias TodoTxt.{Config, Tasks}

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

  @switches [
    file: :string,
    done_file: :string,
    plain: :boolean,
    json: :boolean,
    tui: :boolean,
    help: :boolean,
    version: :boolean
  ]
  @aliases [f: :file, d: :done_file, h: :help]

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
    {kw, rest, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        names = Enum.map_join(invalid, ", ", fn {name, _} -> name end)
        {:usage, "unknown option(s): #{names}"}

      kw[:version] ->
        {:ok, @version}

      kw[:help] ->
        {:ok, TodoTxt.Commands.Help.text()}

      true ->
        run_command(rest, kw, env)
    end
  end

  defp run_command(rest, kw, env) do
    opts =
      %{
        file: kw[:file],
        done_file: kw[:done_file],
        plain: kw[:plain] || false,
        json: kw[:json] || false,
        sort: nil
      }
      |> merge_config(Map.get(env, :config) || Config.load_file())

    env = env |> Map.put_new(:paths, Config.resolve_paths(opts)) |> Map.put(:opts, opts)

    if kw[:tui] do
      case rest do
        [] ->
          with {:ok, lists} <- Tasks.load(env.paths) do
            TodoTxt.Tui.run(Map.merge(env, lists))
          end

        _ ->
          {:usage, "--tui takes no command"}
      end
    else
      case rest do
        # help/listaddons are intercepted before dispatch: they must work
        # even when the task files are unreadable.
        ["help" | _] ->
          TodoTxt.Commands.Help.run([], env)

        ["listaddons" | _] ->
          TodoTxt.Commands.ListAddons.run([], env)

        [cmd | args] ->
          case @commands[cmd] do
            nil -> {:usage, "unknown command #{cmd} (try: todo help)"}
            {mod, sub} -> dispatch(mod, [sub | args], env)
            mod -> dispatch(mod, args, env)
          end

        [] ->
          {:usage, "no command (try: todo help)"}
      end
    end
  end

  defp dispatch(mod, args, env) do
    with {:ok, lists} <- Tasks.load(env.paths) do
      mod.run(args, Map.merge(env, lists))
    end
  end

  # Config-file defaults (spec §5): `COLORS=off|0|false` forces plain
  # output, `LS_SORT=line` makes ls/listall sort by line only.
  # Explicit flags win over config.
  defp merge_config(opts, config) do
    colors_off = String.downcase(config["COLORS"] || "") in ["off", "0", "false"]

    %{
      opts
      | plain: opts.plain or colors_off,
        sort: if(config["LS_SORT"] == "line", do: "line", else: opts.sort)
    }
  end
end
