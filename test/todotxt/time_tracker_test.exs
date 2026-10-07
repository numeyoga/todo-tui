defmodule TodoTxt.TimeTrackerTest do
  use ExUnit.Case, async: true

  alias TodoTxt.TimeTracker

  test "format_minutes handles numbers and strings" do
    assert TimeTracker.format_minutes(0) == "0m"
    assert TimeTracker.format_minutes(45) == "45m"
    assert TimeTracker.format_minutes("45") == "45m"
    assert TimeTracker.format_minutes(60) == "1h"
    assert TimeTracker.format_minutes(90) == "1h30"
    assert TimeTracker.format_minutes(125) == "2h05"
    assert TimeTracker.format_minutes(nil) == nil
    assert TimeTracker.format_minutes("abc") == "abc"
  end
end
