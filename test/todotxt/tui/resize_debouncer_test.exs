defmodule TodoTxt.Tui.ResizeDebouncerTest do
  use ExUnit.Case, async: true

  alias TodoTxt.Tui.ResizeDebouncer

  test "forwards single resize after debounce delay" do
    target = self()
    {:ok, debouncer} = ResizeDebouncer.start(target, debounce_ms: 30)

    send(debouncer, {:terminal_resize, {24, 80}})

    refute_received {:terminal_resize, _}

    assert_receive {:terminal_resize, {24, 80}}, 100
  end

  test "rapid resizes discard intermediate sizes and deliver only the last one" do
    target = self()
    {:ok, debouncer} = ResizeDebouncer.start(target, debounce_ms: 40)

    # Simulate rapid mouse drag resizing: many events in quick succession
    for {r, c} <- [{20, 70}, {22, 75}, {25, 80}, {30, 90}, {35, 100}, {40, 120}] do
      send(debouncer, {:terminal_resize, {r, c}})
      Process.sleep(5)
    end

    # Intermediate sizes must not be received
    refute_received {:terminal_resize, {20, 70}}
    refute_received {:terminal_resize, {22, 75}}
    refute_received {:terminal_resize, {25, 80}}
    refute_received {:terminal_receive, {30, 90}}
    refute_received {:terminal_resize, {35, 100}}

    # Only the last size is received once settled
    assert_receive {:terminal_resize, {40, 120}}, 100

    # No additional messages lingering in mailbox
    refute_receive {:terminal_resize, _}, 50
  end

  test "does not resend if size did not change after flush" do
    target = self()
    {:ok, debouncer} = ResizeDebouncer.start(target, debounce_ms: 20)

    send(debouncer, {:terminal_resize, {24, 80}})
    assert_receive {:terminal_resize, {24, 80}}, 100

    # Send identical size again
    send(debouncer, {:terminal_resize, {24, 80}})
    refute_receive {:terminal_resize, _}, 50
  end

  test "terminates cleanly when monitored process dies" do
    parent = self()

    task =
      Task.async(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, debouncer} = ResizeDebouncer.start(task.pid, debounce_ms: 20)
    ref = Process.monitor(debouncer)

    send(task.pid, :stop)
    Task.await(task)

    assert_receive {:DOWN, ^ref, :process, ^debouncer, :normal}, 200
  end
end
