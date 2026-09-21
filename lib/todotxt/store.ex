defmodule TodoTxt.Store do
  @moduledoc """
  The only module allowed to do file I/O on todo.txt files.

  Missing files read as `{:ok, []}`. Full rewrites go through
  `write_atomic/2` (tmp file + rename).
  """

  alias TodoTxt.Parser

  @spec read(Path.t()) :: {:ok, [TodoTxt.Task.t()]} | {:error, String.t()}
  def read(path) do
    case File.read(path) do
      {:ok, c} -> {:ok, Parser.parse_all(c)}
      {:error, :enoent} -> {:ok, []}
      {:error, r} -> {:error, "cannot read #{path}: #{:file.format_error(r)}"}
    end
  end

  @spec write(Path.t(), [TodoTxt.Task.t()]) :: :ok | {:error, String.t()}
  def write(path, tasks) do
    content = Enum.map_join(tasks, "\n", &Parser.render/1)
    write_atomic(path, if(content == "", do: "", else: content <> "\n"))
  end

  @spec append(Path.t(), [TodoTxt.Task.t()]) :: :ok | {:error, String.t()}
  def append(path, tasks) do
    File.mkdir_p!(Path.dirname(path))
    content = Enum.map_join(tasks, "\n", &Parser.render/1) <> "\n"

    case File.open(path, [:append]) do
      {:ok, f} ->
        write_result = IO.binwrite(f, content)
        close_result = File.close(f)

        case {write_result, close_result} do
          {:ok, :ok} ->
            :ok

          {{:error, r}, _} ->
            {:error, "cannot append #{path}: #{:file.format_error(r)}"}

          {_, {:error, r}} ->
            {:error, "cannot append #{path}: #{:file.format_error(r)}"}
        end

      {:error, r} ->
        {:error, "cannot append #{path}: #{:file.format_error(r)}"}
    end
  end

  @spec append_line(Path.t(), String.t()) :: {:ok, :ok} | {:error, File.posix()}
  def append_line(path, line) do
    File.mkdir_p!(Path.dirname(path))
    File.open(path, [:append], &IO.binwrite(&1, line <> "\n"))
  end

  @spec write_atomic(Path.t(), String.t()) :: :ok | {:error, String.t()}
  def write_atomic(path, content) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, r} -> {:error, "cannot write #{path}: #{:file.format_error(r)}"}
    end
  end
end
