defmodule TodoTxt.Task do
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

  # Stub — implemented in Task 9. Always returns nil; `List.first/1`
  # keeps the inferred type `t() | nil` so `Commands.Do` type-checks
  # the recurrence branch without warnings.
  @spec next_recurrence(t(), Date.t()) :: t() | nil
  def next_recurrence(t, _today), do: List.first([nil, t])

  defp reparse(%__MODULE__{} = t), do: Parser.parse(Parser.render(t), t.line)
end
