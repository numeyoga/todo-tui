defmodule TodoTxt.Tui.NifLoader do
  @moduledoc """
  Ensures the ExRatatui NIF shared library is accessible when running
  from a standalone Erlang escript archive.

  In an escript archive, `Application.app_dir(:ex_ratatui)` resolves to a virtual path
  inside the escript zip file, which OS dynamic linkers (`dlopen` / `LoadLibrary`)
  cannot load directly.

  This module extracts the compiled/precompiled NIF library to a persistent user cache
  directory and points Erlang's code server for `:ex_ratatui` to that location before
  `ExRatatui.Native.ensure_loaded/0` is invoked.
  """

  # Discover the NIF file at compile time
  ext =
    case :os.type() do
      {:win32, _} -> ".dll"
      _ -> ".so"
    end

  nif_file =
    with {:module, ExRatatui.Native} <- Code.ensure_loaded(ExRatatui.Native),
         {:ex_ratatui, rel_path} <- ExRatatui.Native.load_from() do
      basename = Path.basename(rel_path) <> ext

      candidates = [
        Path.join([Mix.Project.build_path(), "lib", "ex_ratatui", "priv", "native", basename]),
        Path.join(["_build", "#{Mix.env()}", "lib", "ex_ratatui", "priv", "native", basename]),
        Path.join(["deps", "ex_ratatui", "priv", "native", basename])
      ]

      Enum.find(candidates, &File.exists?/1)
    else
      _ -> nil
    end

  if nif_file && File.exists?(nif_file) do
    @external_resource nif_file
    @nif_name Path.basename(nif_file)
    @nif_compressed :zlib.gzip(File.read!(nif_file))

    @doc false
    def embedded?, do: true

    @doc false
    def nif_name, do: @nif_name

    @doc false
    def nif_data, do: :zlib.gunzip(@nif_compressed)
  else
    @doc false
    def embedded?, do: false

    @doc false
    def nif_name, do: nil

    @doc false
    def nif_data, do: nil
  end

  @doc """
  Ensures the ExRatatui NIF is loaded. Safe to call multiple times.
  """
  def ensure_loaded do
    if ExRatatui.Native.loaded?() do
      :ok
    else
      do_ensure_loaded()
    end
  end

  defp do_ensure_loaded do
    lib_dir = Application.app_dir(:ex_ratatui)

    if File.dir?(lib_dir) do
      # Running from source / mix run where lib_dir is a real filesystem directory
      ExRatatui.Native.ensure_loaded()
    else
      # Running from an escript archive
      load_from_cache()
    end
  end

  defp load_from_cache do
    cache_dir = resolve_cache_dir()
    ebin_dir = Path.join(cache_dir, "ebin")
    File.mkdir_p!(ebin_dir)

    maybe_extract_nif(cache_dir)

    # Preload all ExRatatui modules while the escript code path is active
    ensure_modules_loaded()

    # Point code server's :ex_ratatui app path to the disk cache
    :code.replace_path(:ex_ratatui, to_charlist(ebin_dir))

    # Trigger native NIF loading
    ExRatatui.Native.ensure_loaded()
  end

  defp maybe_extract_nif(cache_dir) do
    case {nif_name(), nif_data()} do
      {name, data} when is_binary(name) and is_binary(data) ->
        dest_nif = Path.join([cache_dir, "priv", "native", name])

        if not File.exists?(dest_nif) do
          File.mkdir_p!(Path.dirname(dest_nif))
          File.write!(dest_nif, data)
          File.chmod(dest_nif, 0o755)
        end

      _ ->
        :ok
    end
  end

  defp resolve_cache_dir do
    base =
      case :os.type() do
        {:win32, _} ->
          System.get_env("LOCALAPPDATA") ||
            System.get_env("APPDATA") ||
            System.user_home!()

        _ ->
          System.get_env("XDG_CACHE_HOME") ||
            Path.join(System.user_home!(), ".cache")
      end

    Path.join([base, "todotxt", "native", "ex_ratatui"])
  end

  defp ensure_modules_loaded do
    case :application.get_key(:ex_ratatui, :modules) do
      {:ok, mods} ->
        Enum.each(mods, &Code.ensure_loaded/1)

      _ ->
        Code.ensure_loaded(ExRatatui.Native)
        Code.ensure_loaded(ExRatatui)
    end
  end
end
