defmodule TodoTxt.Commands.ListAddons do
  @moduledoc """
  `todo listaddons` — addon listing is not supported.
  """

  def run(_args, _ctx), do: {:ok, "(no addons support)"}
end
