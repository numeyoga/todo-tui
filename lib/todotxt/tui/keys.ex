defmodule TodoTxt.Tui.Keys do
  @moduledoc "Keybinding table: Event.Key -> app message, per mode."

  alias ExRatatui.Event.Key, as: RatatuiKey
  alias TermUI.Event.Key, as: TermUIKey

  @normal %{
    "down" => {:nav, 1},
    "up" => {:nav, -1},
    "tab" => :focus_next,
    "enter" => :activate,
    "esc" => :clear_filter
  }

  @normal_chars %{
    "j" => {:nav, 1},
    "k" => {:nav, -1},
    "h" => :focus_sidebar,
    "l" => :focus_list,
    "x" => :toggle_done,
    " " => :toggle_done,
    "a" => {:open_modal, :add},
    "e" => {:open_modal, :edit},
    "A" => {:open_modal, :append},
    "P" => {:open_modal, :prepend},
    "d" => {:open_modal, :del},
    "p" => {:open_modal, :pri},
    "t" => {:open_modal, :tag},
    "m" => :move,
    "R" => {:open_modal, :archive},
    "L" => :toggle_scope,
    "H" => :toggle_hidden,
    "N" => :edit_note,
    "/" => {:open_modal, :filter},
    "E" => :edit_external,
    "r" => :reload,
    "?" => {:open_modal, :help},
    "q" => :quit
  }

  @doc "Translate a key event to a message for `mode`. :ignore when unbound."
  def msg(key_event, mode) do
    case to_key(key_event) do
      {:release, _} -> :ignore
      {:key, code, mods} -> dispatch(code, mods, mode, key_event)
      _ -> :ignore
    end
  end

  defp dispatch(code, mods, :normal, _orig) when code in ["l", "L"] do
    if "ctrl" in mods, do: :redraw, else: Map.get(@normal_chars, code, :ignore)
  end

  defp dispatch(code, [], :normal, _orig) do
    Map.get(@normal, code) || Map.get(@normal_chars, code, :ignore)
  end

  defp dispatch(code, ["shift"], :normal, _orig)
       when code in ["A", "P", "R", "L", "H", "N", "E", "?"] do
    Map.get(@normal_chars, code, :ignore)
  end

  defp dispatch(_code, _mods, :normal, _orig), do: :ignore

  defp dispatch(code, mods, :input, orig) when code in ["l", "L"] do
    if "ctrl" in mods, do: :redraw, else: {:modal_event, orig}
  end

  defp dispatch(_code, _mods, :input, orig), do: {:modal_event, orig}

  @term_code_map %{
    down: "down",
    up: "up",
    tab: "tab",
    enter: "enter",
    escape: "esc",
    end: "end",
    home: "home"
  }

  def to_key(%RatatuiKey{kind: "release"}), do: {:release, nil}

  def to_key(%RatatuiKey{code: code, modifiers: mods}) do
    {:key, code, mods || []}
  end

  def to_key(%TermUIKey{key: key, modifiers: mods}) do
    {:key, term_key_code(key), term_mods_to_strings(mods)}
  end

  def to_key(_), do: :unknown

  defp term_key_code(key) do
    Map.get_lazy(@term_code_map, key, fn ->
      case key do
        k when is_binary(k) -> k
        k when is_atom(k) -> Atom.to_string(k)
        k when is_integer(k) -> <<k::utf8>>
      end
    end)
  end

  defp term_mods_to_strings(mods) do
    mods
    |> List.wrap()
    |> Enum.map(fn
      :ctrl -> "ctrl"
      :shift -> "shift"
      :alt -> "alt"
      s when is_binary(s) -> s
    end)
  end
end
