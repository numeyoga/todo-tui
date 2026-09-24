defmodule TodoTxt.Editor do
  @moduledoc """
  Opens a file in the user's editor with the real terminal attached.

  Resolution order: `$VISUAL`, `$EDITOR`, then `vi` (blank values count
  as unset). The command line is split shell-style (`code --wait`,
  `emacs -nw`…), then spawned via a `:nouse_stdio` port: the editor
  inherits the VM's stdin/stdout/stderr — the actual tty — instead of
  the pipes `System.cmd` would install, so full-screen editors like
  vim and nano work.
  """

  @doc "The editor command line: `$VISUAL`, `$EDITOR`, or `\"vi\"`."
  @spec resolve() :: String.t()
  def resolve do
    Enum.find_value(["VISUAL", "EDITOR"], "vi", &env_editor/1)
  end

  defp env_editor(var) do
    v = System.get_env(var)
    if is_binary(v) and String.trim(v) != "", do: v
  end

  @doc "Splits an editor command line into `[binary | args]`."
  @spec split(String.t()) :: [String.t()]
  def split(cmd), do: OptionParser.split(cmd)

  @doc """
  Opens `path` in `editor` (default `resolve/0`), blocking until it
  exits. Returns `:ok` on exit status 0, `{:error, msg}` otherwise.
  """
  @spec open(Path.t(), String.t()) :: :ok | {:error, String.t()}
  def open(path, editor \\ resolve()) do
    case split(editor) do
      [] ->
        {:error, "no editor configured"}

      [bin | args] ->
        case :os.find_executable(String.to_charlist(bin)) do
          false -> {:error, "editor not found: #{bin}"}
          exe -> exe |> spawn_port(args ++ [path]) |> await()
        end
    end
  end

  # :nouse_stdio — the child keeps the VM's fds 0/1/2 (the tty); the
  # port protocol rides on fds 3/4 and only :exit_status matters to us.
  defp spawn_port(exe, args),
    do: Port.open({:spawn_executable, exe}, [:nouse_stdio, :exit_status, args: args])

  defp await(port) do
    # The port dies with the spawned program (fds 3/4 hit EOF), so no
    # Port.close needed — exit_status is just the report.
    receive do
      {^port, {:exit_status, status}} ->
        if status == 0, do: :ok, else: {:error, "editor exited #{status}"}
    end
  end
end
