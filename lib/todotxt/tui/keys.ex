defmodule TodoTxt.Tui.Keys do
  @moduledoc "Keybinding table: Event.Key -> app message, per mode."

  alias TermUI.Event

  @normal %{
    :down => {:nav, 1},
    :up => {:nav, -1},
    :tab => :focus_next,
    :enter => :activate,
    :escape => :clear_filter
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
    "m" => :move,
    "R" => {:open_modal, :archive},
    "L" => :toggle_scope,
    "/" => {:open_modal, :filter},
    "E" => :edit_external,
    "r" => :reload,
    "?" => {:open_modal, :help},
    "q" => :quit
  }

  @doc "Translate a key event to a message for `mode`. :ignore when unbound."
  def msg(%Event.Key{key: key, modifiers: mods}, :normal)
      when key in [?\f, "\f"] or key in ["l", "L", :l] do
    if is_list(mods) and :ctrl in mods do
      :redraw
    else
      if is_binary(key) and mods == [], do: Map.get(@normal_chars, key, :ignore), else: :ignore
    end
  end

  def msg(%Event.Key{key: key}, :normal) when is_atom(key),
    do: Map.get(@normal, key, :ignore)

  def msg(%Event.Key{key: key, modifiers: mods}, :normal) when is_binary(key),
    do: if(mods == [], do: Map.get(@normal_chars, key, :ignore), else: :ignore)

  def msg(%Event.Key{key: key, modifiers: mods} = ev, :input)
      when key in [?\f, "\f"] or key in ["l", "L", :l] do
    if is_list(mods) and :ctrl in mods, do: :redraw, else: {:modal_event, ev}
  end

  def msg(%Event.Key{} = ev, :input), do: {:modal_event, ev}
  def msg(_, _), do: :ignore
end
