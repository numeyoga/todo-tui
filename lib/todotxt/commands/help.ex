defmodule TodoTxt.Commands.Help do
  @moduledoc """
  `todo help` (also `todo -h`) — print the command list.
  """

  @doc "The static help text, grouped like the spec's command table."
  @spec text() :: String.t()
  def text do
    """
    todo — CLI todo.txt

    Ajout / édition:
      add|a TEXT...          add a task (creation date = today)
      append|app N TEXT...   append text to task N
      prepend|prep N TEXT... prepend text to task N
      replace N TEXT...      replace task N's text
      edit                   open todo.txt in $EDITOR

    Cycle de vie:
      do N                   mark task N done (recurs if recur: tag)
      undo N                 reopen task N
      del|rm N [TERM]        delete task N, or strip TERM from it
      pri N X / depri N      set / remove priority (A-Z)
      move|mv N done|todo    move task N between files

    Listage:
      ls|list [TERMS...]     list open tasks (AND filter)
      listall|lsa [TERMS...] list todo.txt + done.txt
      listproj|lsprj         list projects
      listcon|lsc            list contexts
      listpri|lspr [P]       list priorities / tasks at priority P
      due                    tasks bucketed by due: date
      agenda                 next 14 days + upcoming t: thresholds

    Extensions:
      listaddons             list addons (unsupported)

    Maintenance:
      archive                move done tasks to done.txt
      dedupe                 drop duplicate lines in todo.txt
      report                 append "DATE <open> <done>" to report.txt

    Méta:
      help, -h               this help
      --version              print version
    """
    |> String.trim_trailing()
  end

  def run(_args, _ctx), do: {:ok, text()}
end
