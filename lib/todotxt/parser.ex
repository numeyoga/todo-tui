defmodule TodoTxt.Parser do
  alias TodoTxt.Task

  @tag_re ~r/^([A-Za-z][A-Za-z0-9_-]*):(\S+)$/

  def parse(line, line_no) do
    raw = String.trim_trailing(line) |> String.trim_trailing("\r")
    tokens = String.split(raw, ~r/\s+/, trim: true)

    {done, tokens} =
      case tokens do
        ["x" | rest] -> {true, rest}
        _ -> {false, tokens}
      end

    {completion_date, tokens} = if done, do: take_date(tokens), else: {nil, tokens}

    {priority, tokens} =
      case {done, tokens} do
        {false, [<<"(", p, ")">> | rest]} when p in ?A..?Z -> {p, rest}
        _ -> {nil, tokens}
      end

    {creation_date, tokens} = take_date(tokens)

    %Task{
      line: line_no,
      raw: raw,
      done: done,
      completion_date: completion_date,
      priority: priority,
      creation_date: creation_date,
      description: Enum.join(tokens, " "),
      projects: for(<<"+", _::binary>> = t <- tokens, String.length(t) > 1, do: t),
      contexts: for(<<"@", _::binary>> = t <- tokens, String.length(t) > 1, do: t),
      tags: extract_tags(tokens)
    }
  end

  def render(%Task{} = t) do
    [
      if(t.done, do: "x"),
      if(t.done && t.completion_date, do: Date.to_string(t.completion_date)),
      if(!t.done && t.priority, do: <<"(", t.priority, ")">>),
      if(t.creation_date, do: Date.to_string(t.creation_date)),
      t.description
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def parse_all(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {l, _} -> String.trim(l) == "" end)
    |> Enum.map(fn {l, i} -> parse(l, i) end)
  end

  defp take_date([tok | rest]) do
    case Date.from_iso8601(tok) do
      {:ok, d} -> {d, rest}
      _ -> {nil, [tok | rest]}
    end
  end

  defp take_date([]), do: {nil, []}

  defp extract_tags(tokens) do
    for t <- tokens,
        [_, k, v] <- [Regex.run(@tag_re, t)],
        not String.contains?(t, "://"),
        into: %{},
        do: {k, v}
  end
end
