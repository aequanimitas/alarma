defmodule Alarma do
  @moduledoc false

  defmodule Tagapamahala do
    def start(name, handler_list) do
      __MODULE__
      |> spawn(:init, [handler_list])
      |> Process.register(name)
    end

    def init(handler_list), do: handler_list |> initialize() |> loop()

    @doc """
    Initializes event handlers by calling their init function
    """
    def initialize([]), do: []
    def initialize([{handler, init_data} | tail]) do
      [{handler, handler.init(init_data)} | initialize(tail)]
    end

    def stop(name) do
      send(name, {self(), :stop})
      receive do
        {:reply, reply} ->
          reply
      end
    end

    def terminate([]), do: []
    def terminate([{handler, data} | tail]) do
      [{handler, handler.terminate(data)} | terminate(tail)]
    end

    @doc """
    """
    def add_handler(name, handler, init_data), do: call(name, {:add_handler, handler, init_data})
    def delete_handler(name, handler), do: call(name, {:delete_handler, handler})
    def get_data(name, handler), do: call(name, {:get_data, handler})
    def send_event(name, event), do: call(name, {:send_event, event})


    ## Handle messages outside the loop for flexibility
    def handle_msg({:add_handler, handler, init_data}, loop_data) do
      {:ok, [{handler, handler.init(init_data)} | loop_data]}
    end

    def handle_msg({:delete_handler, handler}, loop_data) do
      case List.keyfind(loop_data, handler, 0) do
        nil ->
          {{:error, :instance}, loop_data}
        {handler, data} ->
          reply = {data, handler.terminate(data)}
          new_loop_data = List.keydelete(loop_data, handler, 0)
          {reply, new_loop_data}
      end
    end

    def handle_msg({:get_data, handler}, loop_data) do
      case List.keyfind(loop_data, handler, 0) do
        nil ->
          {{:error, :instance}, loop_data}
        {_handler, data} ->
          reply = {data, handler.terminate(data)}
          {{:data, data}, loop_data}
      end
    end

    def handle_msg({:send_event, e}, loop_data) do
      {:ok, event(e, loop_data)}
    end

    def event(_event, []), do: []
    def event(e, [{handler, data} | tail]) do
      [{handler, handler.handle_event(e, data)} | event(e, tail)]
    end

    # call-reply-loop pattern, recurring theme/pattern among processes
    def call(name, msg) do
      send(name, {:request, self(), msg})
      receive do
        {:reply, reply} ->
          reply
      end
    end

    def reply(to, msg), do: send(to, {:reply, msg})

    def loop(state) do
      receive do
        {:request, from, msg} ->
          {reply, new_state} = handle_msg(msg, state)
          reply(from, reply)
          loop(new_state)
        {:stop, from} ->
          reply(from, terminate(state))
      end
    end
  end

  defmodule IOHandler do
    @moduledoc """
    Filters out events that are:
    - {:raise_alarm, id, type}
    - {:clear_alarm, id, type}

    All other events are ignored
    """

    def init(count), do: count
    def terminate(count), do: {:count, count}
    
    def handle_event({:raise_alarm, id, alarm}, count) do
      print(:alarm, id, alarm, count)
      count + 1
    end
    
    def handle_event({:clear_alarm, id, alarm}, count) do
      print(:clear, id, alarm, count)
      count + 1
    end

    def handle_event(_, count), do: count

    def print(type, id, alarm, count) do
      date = fmt(:erlang.date())
      time = fmt(:erlang.time())
      :io.format("#~w, ~s, ~s, ~w, ~w, ~p~n", [count, date, time, type, id, alarm])
    end

    def fmt({a, b, c}) do
      a = a |> Integer.to_charlist()
      b = b |> Integer.to_charlist()
      c = c |> Integer.to_charlist()
      [a, ":", b, ":", c]
    end
  end

  defmodule LogHandler do
    @moduledoc """
    File logging. Yay!
    """
    def init(filename) do
      {:ok, io_device} = File.open(filename, [:write])
      io_device
    end

    def handle_event({action, id, event}, io_device) do
      {mega_sec, sec, micro_sec} = :erlang.now()
      log_format = "~w, ~w, ~w, ~w, ~w, ~p~n"
      log_vars = [mega_sec, sec, micro_sec, action, id, event]
      args = :io.format(io_device, log_format, log_vars)
      io_device
    end

    def handle_event(_, io_device), do: io_device

    def terminate(io_device), do: File.close(io_device)
  end
end
