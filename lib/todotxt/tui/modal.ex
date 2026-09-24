defmodule TodoTxt.Tui.Modal do
  @moduledoc "Builds modal widget state per action."

  alias TermUI.Event
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TodoTxt.Tui.State

  @help_text "j/k nav · Tab focus · Enter applique · x/space do-undo · a add · " <>
               "e edit · A/P append/prepend · p prio · d del · m move · " <>
               "R archive · / filter · E $EDITOR · r reload · Esc annule · q quit"

  @doc "Modal map `%{action:, widget:, widget_mod:}` (+`:line` when task-bound)."
  def open(:add, _s), do: text_modal(:add, "", "New task: ")
  def open(:filter, s), do: text_modal(:filter, Enum.join(s.filter_terms, " "), "Filter: ")

  def open(:edit, s), do: text_modal(:edit, selected_raw(s), "Edit: ") |> with_line(s)
  def open(:append, s), do: text_modal(:append, "", "Append: ") |> with_line(s)
  def open(:prepend, s), do: text_modal(:prepend, "", "Prepend: ") |> with_line(s)

  def open(:pri, s) do
    items = Enum.map(?A..?Z, &<<&1>>) ++ ["(aucune)"]
    {:ok, w} = PickList.init(%{items: items, title: "Priorité", width: 20, height: 12})
    %{action: :pri, widget: w, widget_mod: PickList, line: selected_line(s)}
  end

  def open(:del, s) do
    confirm(:del, "Supprimer", "Supprimer la tâche #{selected_line(s)} ?")
    |> Map.put(:line, selected_line(s))
  end

  def open(:archive, s) do
    done = s |> State.counts() |> Map.get(:done)
    confirm(:archive, "Archiver", "Archiver #{done} tâche(s) faite(s) ?")
  end

  def open(:help, _s) do
    props =
      AlertDialog.new(
        type: :info,
        title: "Aide",
        message: @help_text,
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

  defp text_modal(action, value, prompt) do
    {:ok, w} = TextInput.init(TextInput.new(value: value, placeholder: prompt, width: 60))

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

  defp confirm(action, title, message) do
    props =
      AlertDialog.new(
        type: :confirm,
        title: title,
        message: message,
        on_result: fn r -> send(self(), {:dialog_result, r}) end
      )

    {:ok, w} = AlertDialog.init(props)
    %{action: action, widget: AlertDialog.show(w), widget_mod: AlertDialog}
  end
end
