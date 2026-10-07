defmodule TodoTxt.Tui.RatatuiAppTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Event.{Key, Resize}
  alias ExRatatui.Runtime
  alias TodoTxt.Tui

  defp fake_io(pid) do
    %{
      read: fn _ -> {:ok, "1 First task\n2 Second task\n"} end,
      write: fn p, ts ->
        if pid, do: send(pid, {:write, p, ts})
        :ok
      end,
      append: fn p, t ->
        if pid, do: send(pid, {:append, p, t})
        :ok
      end,
      exists?: fn _ -> true end,
      stat: fn _ -> {:ok, %{mtime: {{2026, 1, 1}, {0, 0, 0}}}} end
    }
  end

  defp test_env(caller \\ self()) do
    %{
      paths: %{todo: "todo.txt", done: "done.txt"},
      tasks: [
        %TodoTxt.Task{line: 1, raw: "First task", description: "First task"},
        %TodoTxt.Task{line: 2, raw: "Second task", description: "Second task"}
      ],
      done_tasks: [],
      io: fake_io(caller),
      plain: true,
      today: Date.utc_today(),
      caller: caller
    }
  end

  test "starts in headless test mode, inspects snapshot, and quits cleanly" do
    env = test_env()
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    snap = Runtime.snapshot(pid)
    assert snap.dimensions == {80, 24}
    assert snap.polling_enabled? == false
    assert snap.render_count >= 1

    # Inject 'j' (nav down)
    assert :ok == Runtime.inject_event(pid, %Key{code: "j", modifiers: []})

    # Inject resize
    assert :ok == Runtime.inject_event(pid, %Resize{width: 100, height: 30})

    # Inject quit 'q'
    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "modal interaction via injected Ratatui events: open add modal, type, and submit" do
    test_pid = self()
    env = test_env(test_pid)
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    # Press 'a' to open add modal
    assert :ok == Runtime.inject_event(pid, %Key{code: "a", modifiers: []})

    # Type "Buy milk"
    for char <- String.graphemes("Buy milk") do
      assert :ok == Runtime.inject_event(pid, %Key{code: char, modifiers: []})
    end

    # Submit with Enter
    assert :ok == Runtime.inject_event(pid, %Key{code: "enter", modifiers: []})

    # Verify task was added and written through IO
    assert_receive {:append, "todo.txt", tasks}, 1000
    assert Enum.any?(tasks, &(&1.description == "Buy milk"))

    # Terminate
    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "modal cancel via escape key" do
    env = test_env()
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    # Press 'a' to open add modal
    assert :ok == Runtime.inject_event(pid, %Key{code: "a", modifiers: []})

    # Press 'esc' to cancel modal
    assert :ok == Runtime.inject_event(pid, %Key{code: "esc", modifiers: []})

    # Quitting works directly because we are back to normal mode
    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "clears text input with Ctrl+U before submitting" do
    test_pid = self()
    env = test_env(test_pid)
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    # Open add modal
    assert :ok == Runtime.inject_event(pid, %Key{code: "a", modifiers: []})

    # Type "Wrong text"
    for char <- String.graphemes("Wrong text") do
      assert :ok == Runtime.inject_event(pid, %Key{code: char, modifiers: []})
    end

    # Clear input with Ctrl+U
    assert :ok == Runtime.inject_event(pid, %Key{code: "u", modifiers: ["ctrl"]})

    # Type "Correct text"
    for char <- String.graphemes("Correct text") do
      assert :ok == Runtime.inject_event(pid, %Key{code: char, modifiers: []})
    end

    # Submit
    assert :ok == Runtime.inject_event(pid, %Key{code: "enter", modifiers: []})

    assert_receive {:append, "todo.txt", tasks}, 1000
    assert Enum.any?(tasks, &(&1.description == "Correct text"))

    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "priority modal selection with down arrow and enter" do
    test_pid = self()
    env = test_env(test_pid)
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    # Open priority modal with 'p'
    assert :ok == Runtime.inject_event(pid, %Key{code: "p", modifiers: []})

    # Press down arrow to move down in priority list
    assert :ok == Runtime.inject_event(pid, %Key{code: "down", modifiers: []})

    # Submit selection with Enter
    assert :ok == Runtime.inject_event(pid, %Key{code: "enter", modifiers: []})

    # Priority should be persisted via write
    assert_receive {:write, "todo.txt", _tasks}, 1000

    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "external editor request sends exit message to caller" do
    test_pid = self()
    env = test_env(test_pid)
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    ref = Process.monitor(pid)
    # Press 'E' (Shift+E)
    assert :ok == Runtime.inject_event(pid, %Key{code: "E", modifiers: ["shift"]})

    # Caller receives {:tui_exit, :edit}
    assert_receive {:tui_exit, :edit}, 1000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end

  test "Ctrl+L triggers redraw sequence and clears screen" do
    env = test_env()
    {:ok, pid} = Tui.start_link(name: nil, test_mode: {80, 24}, env: env)

    snap_before = Runtime.snapshot(pid)
    assert snap_before.render_count >= 1

    # Inject Ctrl+L
    assert :ok == Runtime.inject_event(pid, %Key{code: "l", modifiers: ["ctrl"]})

    # Let the GenServer process the subsequent :redraw_finish info message
    Process.sleep(50)

    snap_after = Runtime.snapshot(pid)
    assert snap_after.render_count >= snap_before.render_count + 2

    sys_state = :sys.get_state(pid)
    assert sys_state.user_state.status == "redessiné"
    assert sys_state.user_state.redraw_clearing == false

    # Terminate
    ref = Process.monitor(pid)
    assert :ok == Runtime.inject_event(pid, %Key{code: "q", modifiers: []})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end
end
