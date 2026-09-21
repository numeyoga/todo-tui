defmodule TodoTxtTest do
  use ExUnit.Case

  test "cli module exists" do
    Code.ensure_loaded!(TodoTxt.CLI)
    assert function_exported?(TodoTxt.CLI, :main, 1)
  end
end
