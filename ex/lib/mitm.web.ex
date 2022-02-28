defmodule Mitm.Web do
  #    subs = :persistent_term.get(:mitm_subscriber, nil)

  def headers_json(headers) do
    Map.merge(headers, %{"Content-Type" => "application/json"})
  end

  def headers_cors(headers) do
    Map.merge(
      headers,
      %{
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, POST, HEAD, PUT, DELETE",
        "Access-Control-Allow-Headers" =>
          "Cache-Control, Pragma, Origin, Authorization, Content-Type, X-Requested-With"
      }
    )
  end

  def serve_json(term, h, s) do
    json_str = JSX.encode!(term)
    {code, headersReply, binReply, s} = :stargate_plugin.serve_static_bin(json_str, h, s)

    headersReply =
      headersReply
      |> headers_json()
      |> headers_cors()

    {code, headersReply, binReply, s}
  end

  def http(:GET, "/subscribe", q, h, _, s) do
    IO.inspect(q)

    key = :os.system_time(1000)
    {:ok, pid} = GenServer.start(MitmJsonWorker, %{})
    :ets.insert(:mitm_web_workers, {key, pid})

    page = JSX.encode!(%{result: "ok", token: "#{key}"})

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    headers = headers_cors(headers)
    {code, headers, body, s}
  end

  def http(:GET, "/poll", q, h, _, s) do
    %{"token" => token} = q
    token = String.to_integer(token)
    res = :ets.lookup(:mitm_web_workers, token)

    # page = JSX.encode! %{result: "ok", token: key} 
    page =
      case res do
        [{_, pid}] ->
          send(pid, {:poll_data, self()})

          data =
            receive do
              {:data, d} ->
                JSX.encode!(%{result: "ok", packets: d})
            after
              5000 ->
                JSX.encode!(%{result: "error", error: "timeout"})
            end

        _ ->
          JSX.encode!(%{result: "error", error: "closed"})
      end

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    headers = headers_cors(headers)
    {code, headers, body, s}
  end

  def http(:POST, "/push", q, h, data, s) do
    IO.inspect({:push, data})
    %{"token" => token} = q
    token = String.to_integer(token)

    res = :ets.lookup(:workers, token)

    # page = JSX.encode! %{result: "ok", token: key} 
    page =
      case res do
        [{_, pid}] ->
          if Process.alive?(pid) do
            send(pid, {:push_data, data, self()})

            data =
              receive do
                :sent_ok ->
                  "ok;0"
              after
                5000 ->
                  "error;timeout"
              end
          else
            "error;closed"
          end

        _ ->
          "error;closed"
      end

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    headers = headers_cors(headers)
    {code, headers, body, s}
  end

  def http(verb, path, q, h, _, s) do
    IO.inspect({verb, path, q, h})
  end
end

defmodule MitmJsonWorker do
  use GenServer

  def init(args) do
    :erlang.send_after(30000, self(), :tick)
    :persistent_term.put(:mitm_subscriber, self())

    {:ok, %{closed: false, buf: [], lastpoll: :os.system_time(1000)}}
  end

  def handle_info(:tick, state) do
    if :os.system_time(1000) - state.lastpoll > 30000 do
      {:stop, :timeout}
    else
      :erlang.send_after(1000, self(), :tick)
      {:noreply, state}
    end
  end

  def handle_info({:received, conn, side, pkts}, state) do
    # IO.puts("got data #{inspect({side, pkts})}")

    pkts =
      Enum.map(pkts, fn pkt ->
        %{
          conn: 1,
          side: side,
          msg: pkts
        }
      end)

    {:noreply, %{state | buf: state.buf ++ pkts}}
  end

  def handle_info({:poll_data, from}, state) do
    send(from, {:data, state.buf})

    if state.closed do
      {:stop, :closed}
    else
      {:noreply, %{state | buf: [], lastpoll: :os.system_time()}}
    end
  end
end

defmodule DofusProxy do
  def route(source, dest, dest_port) do
    res =
      case {source, dest, dest_port} do
        {_, _, 5555} ->
          %{module: DofusMitmCon}
      end
  end

  def start() do
    specs = [
      %{port: 31300, router: __MODULE__, listener_type: :sock5}
    ]

    {:ok, _} = Mitme.Acceptor.Supervisor.start_link(specs)
  end
end

defmodule DofusMitmCon do
  use GenServer

  def init(_) do
    {:ok, %{}}
  end

  def connect_addr(address, port) do
    {address, port}
  end

  def on_connect(flow = %{dest: socket}) do
    case socket do
      {:sslsocket, x} ->
        nil

      _ ->
        :inet.setopts(socket, [{:active, true}, :binary])
    end

    flow
  end

  def on_close(_socket, state) do
    state
  end

  def proc_packet(side, p, s) do
    subs = :persistent_term.get(:mitm_subscriber, nil)

    if subs do
      send(subs, {:received, side, pkts})
    end

    {:send, p, s}
  end
end
