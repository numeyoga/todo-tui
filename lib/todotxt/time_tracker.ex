defmodule TodoTxt.TimeTracker do
  @moduledoc """
  Utilities for working with `min:` tags (time tracking in minutes).
  """

  @doc """
  Formats minutes into a human-readable duration (e.g. 45 -> "45m", 90 -> "1h30", 120 -> "2h").
  """
  def format_minutes(nil), do: nil

  def format_minutes(mins) when is_binary(mins) do
    case Integer.parse(mins) do
      {m, ""} -> format_minutes(m)
      _ -> mins
    end
  end

  def format_minutes(m) when is_integer(m) and m >= 0 do
    hours = div(m, 60)
    rem_m = rem(m, 60)

    cond do
      hours == 0 ->
        "#{rem_m}m"

      rem_m == 0 ->
        "#{hours}h"

      true ->
        "#{hours}h" <> String.pad_leading(to_string(rem_m), 2, "0")
    end
  end

  def format_minutes(other), do: to_string(other)
end
