defmodule TodoTxt.Tui.Modal do
  @moduledoc "Builds modal widget state per action."

  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TodoTxt.Tui.State

  @help_text "j/k nav · Tab focus · Enter applique · x/space do-undo · a add · " <>
               "e edit · A/P append/prepend · p prio · t tag · d del · m move · " <>
               "R archive · L scope · H hidden · N note · / filter · E $EDITOR · r reload · ^L redessiner · Esc annule · q quit"

  @doc "Modal map `%{action:, widget:, widget_mod:}` (+`:line` when task-bound)."
  def open(:add, s), do: text_modal(:add, "", "New task: ", Map.get(s, :width, 80))

  def open(:filter, s),
    do: text_modal(:filter, Enum.join(s.filter_terms, " "), "Filter: ", Map.get(s, :width, 80))

  def open(:edit, s),
    do:
      text_modal(:edit, selected_raw(s), "Edit: ", Map.get(s, :width, 80))
      |> with_line(s)

  def open(:tag, s),
    do:
      text_modal(:tag, "", "Tag: ", Map.get(s, :width, 80))
      |> with_line(s)

  def open(:append, s),
    do: text_modal(:append, "", "Append: ", Map.get(s, :width, 80)) |> with_line(s)

  def open(:prepend, s),
    do: text_modal(:prepend, "", "Prepend: ", Map.get(s, :width, 80)) |> with_line(s)

  def open(:pri, s) do
    items = Enum.map(?A..?Z, &<<&1>>) ++ ["(aucune)"]
    selected_task = State.selected_task(s)

    init_idx =
      if selected_task && selected_task.priority do
        pri_char = <<selected_task.priority>>
        Enum.find_index(items, &(&1 == pri_char)) || 0
      else
        0
      end

    scroll = if init_idx >= 9, do: init_idx - 8, else: 0

    {:ok, w} = PickList.init(%{items: items, title: "Priorité", width: 28, height: 12})
    w = %{w | selected_index: init_idx, scroll_offset: scroll}
    %{action: :pri, widget: w, widget_mod: PickList, line: selected_line(s)}
  end

  def open(:del, s) do
    confirm(:del, "Supprimer", "Supprimer la tâche #{selected_line(s)} ?", s)
    |> Map.put(:line, selected_line(s))
  end

  def open(:archive, s) do
    done = s |> State.counts() |> Map.get(:done)
    confirm(:archive, "Archiver", "Archiver #{done} tâche(s) faite(s) ?", s)
  end

  def open(:help, s) do
    border_style =
      if Map.get(s, :plain, false), do: Style.new(attrs: [:dim]), else: Style.new(fg: :cyan)

    props =
      AlertDialog.new(
        type: :info,
        title: "Aide",
        message: @help_text,
        border_style: border_style,
        on_result: fn r -> send(self(), {:dialog_result, r}) end
      )

    {:ok, w} = AlertDialog.init(props)
    %{action: :help, widget: AlertDialog.show(w), widget_mod: AlertDialog}
  end

  defp selected_raw(s) do
    case State.selected_task(s) do
      nil -> ""
      t -> t.raw
    end
  end

  defp selected_line(s) do
    case State.selected_task(s) do
      nil -> nil
      t -> t.line
    end
  end

  defp text_modal(action, value, prompt, screen_width) do
    sw = screen_width || 80
    width = max(sw - String.length(prompt) - 2, 80)
    {:ok, w} = TextInput.init(TextInput.new(value: value, placeholder: prompt, width: width))

    %{
      action: action,
      widget: w |> TextInput.set_focused(true) |> move_cursor_end(),
      widget_mod: TextInput,
      prompt: prompt
    }
  end

  defp move_cursor_end(w) do
    case TextInput.get_value(w) do
      "" ->
        w

      _ ->
        {:ok, w2} = TextInput.handle_event(%Event.Key{key: :end, modifiers: [:ctrl]}, w)
        w2
    end
  end

  defp with_line(modal, s), do: Map.put(modal, :line, selected_line(s))

  defp confirm(action, title, message, s) do
    border_style =
      if Map.get(s, :plain, false), do: Style.new(attrs: [:dim]), else: Style.new(fg: :cyan)

    props =
      AlertDialog.new(
        type: :confirm,
        title: title,
        message: message,
        border_style: border_style,
        on_result: fn r -> send(self(), {:dialog_result, r}) end
      )

    {:ok, w} = AlertDialog.init(props)
    %{action: action, widget: AlertDialog.show(w), widget_mod: AlertDialog}
  end
end
