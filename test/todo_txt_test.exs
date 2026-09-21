defmodule TodoTxtTest do
  use ExUnit.Case

  test "cli module exists" do
    assert function_exported?(TodoTxt.CLI, :main, 1)
  end
end
