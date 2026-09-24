defmodule TodoTxt.Task do
  @moduledoc """
  A parsed todo.txt line. `line` is its 1-based position in the source
  file; transformations re-render `raw` via `TodoTxt.Parser`.
  """

  @enforce_keys [:line]
  defstruct line: nil,
            raw: "",
            done: false,
            completion_date: nil,
            priority: nil,
            creation_date: nil,
            description: "",
            projects: [],
            contexts: [],
            tags: %{}

  @type t :: %__MODULE__{}

  alias TodoTxt.Parser

  def complete(%__MODULE__{} = t, today) do
    reparse(%{t | done: true, completion_date: today, priority: nil})
  end

  def uncomplete(%__MODULE__{} = t), do: reparse(%{t | done: false, completion_date: nil})
  def set_priority(%__MODULE__{} = t, p) when p in ?A..?Z, do: reparse(%{t | priority: p})
  def set_priority(%__MODULE__{} = t, nil), do: reparse(%{t | priority: nil})
  def set_text(%__MODULE__{} = t, s), do: reparse(%{t | description: s})
  def append_text(%__MODULE__{} = t, s), do: set_text(t, String.trim(t.description <> " " <> s))
  def prepend_text(%__MODULE__{} = t, s), do: set_text(t, String.trim(s <> " " <> t.description))

  @doc """
  Build the next occurrence of a recurring task (`recur:` tag).

  `recur:+Nu` shifts from the completion date `today`; `recur:Nu`
  (strict) shifts from the old `due:` date, falling back to `today`
  when absent or invalid. Units: `d`ays, `w`eeks, `m`onths, `y`ears.

  Returns a fresh task (re-parsed, `line` 0 — the caller assigns the
  real number) with `due:` recomputed, `creation_date` = `today`, and
  priority/projects/contexts/other tags preserved. A `t:` threshold
  is shifted by the same recurrence: from its own date in strict
  mode (preserving the `t:`↔`due:` offset), from `today` otherwise.
  An unparseable `t:` is dropped. `nil` when the task has no valid
  `recur:` tag.
  """
  @spec next_recurrence(t(), Date.t()) :: t() | nil
  def next_recurrence(%__MODULE__{tags: %{"recur" => r}} = t, today) do
    with {:ok, strict, n, unit} <- parse_recur(r),
         base when not is_nil(base) <- recur_base(t, strict, today) do
      new_due = shift(base, n, unit)

      desc =
        t.description
        |> update_tag("due", Date.to_string(new_due))
        |> shift_threshold(t.tags["t"], strict, n, unit, today)

      raw =
        [if(t.priority, do: <<"(", t.priority, ")">>), Date.to_string(today), desc]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      Parser.parse(raw, 0)
    else
      _ -> nil
    end
  end

  def next_recurrence(_, _), do: nil

  defp parse_recur(r) when is_binary(r) do
    case Regex.run(~r/^(\+?)(\d+)([dwmy])$/, r) do
      [_, plus, n, u] -> {:ok, plus == "", String.to_integer(n), u}
      _ -> :error
    end
  end

  defp parse_recur(_), do: :error

  defp recur_base(t, strict, today) do
    if strict do
      case t.tags["due"] && Date.from_iso8601(t.tags["due"]) do
        {:ok, d} -> d
        _ -> today
      end
    else
      today
    end
  end

  defp shift_threshold(desc, nil, _strict, _n, _u, _today), do: desc

  defp shift_threshold(desc, v, strict, n, unit, today) do
    case Date.from_iso8601(v) do
      {:ok, old_t} ->
        base = if strict, do: old_t, else: today
        update_tag(desc, "t", Date.to_string(shift(base, n, unit)))

      _ ->
        remove_tag(desc, "t")
    end
  end

  defp remove_tag(desc, key) do
    desc
    |> String.replace(~r/\s*\b#{key}:\S+/, "")
    |> String.trim()
  end

  defp shift(d, n, "d"), do: Date.add(d, n)
  defp shift(d, n, "w"), do: Date.add(d, n * 7)
  defp shift(d, n, "m"), do: Date.shift(d, month: n)
  defp shift(d, n, "y"), do: Date.shift(d, year: n)

  defp update_tag(desc, key, value) do
    re = ~r/\b#{key}:\S+/

    if Regex.match?(re, desc),
      do: Regex.replace(re, desc, "#{key}:#{value}"),
      else: desc <> " #{key}:#{value}"
  end

  defp reparse(%__MODULE__{} = t), do: Parser.parse(Parser.render(t), t.line)
end
