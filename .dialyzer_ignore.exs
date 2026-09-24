[
  # TermUI.Runtime.option() omits :env, yet Runtime.init/1 forwards all
  # opts to the root module's init/1, which reads env from them.
  {"lib/todotxt/tui.ex", :no_return}
]
