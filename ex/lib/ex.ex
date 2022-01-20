defmodule Ex do
  @moduledoc """
  Documentation for `Ex`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Ex.hello()
      :world

  """
  def run do
    :ets.new(:workers, [:named_table, :public])

    port = 9010

    webserver = %{
      ip: {0, 0, 0, 0},
      port: port,
      hosts: %{
        {:http, "*"} => {ProxyApp, %{}}
      }
    }

    {:ok, _Pid} = :stargate.warp_in(webserver)
  end
end

defmodule ProxyApp do
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

  def http(:OPTIONS, _, _q, _h, _body, s) do
    {200, headers_cors(%{}), "", s}
  end

  def http(:GET, "/connect", q, h, _, s) do
    IO.inspect(q)
    %{"host" => host, "port" => port} = q
    port = String.to_integer(port)

    key = :os.system_time(1000)
    {:ok, pid} = GenServer.start(ConnWorker, %{host: host, port: port})
    :ets.insert(:workers, {key, pid})

    # page = JSX.encode! %{result: "ok", token: key} 
    page = inspect(key)

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    {code, headers, body, s}
  end

  def http(:GET, "/poll", q, h, _, s) do
    IO.inspect(q)
    %{"token" => token} = q
    token = String.to_integer(token)

    res = :ets.lookup(:workers, token)

    # page = JSX.encode! %{result: "ok", token: key} 
    page =
      case res do
        {_, pid} ->
          send(pid, {:poll_data, self()})

          data =
            receive do
              {:data, d} ->
                "ok;" <> d
            after
              5000 ->
                "error;timeout"
            end

        _ ->
          "error;closed"
      end

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    {code, headers, body, s}
  end

  def http(:POST, "/push", q, h, data, s) do
    IO.inspect(q)
    %{"token" => token} = q
    token = String.to_integer(token)

    res = :ets.lookup(:workers, token)

    # page = JSX.encode! %{result: "ok", token: key} 
    page =
      case res do
        {_, pid} ->
          send(pid, {:push_data, data, self()})

          data =
            receive do
              :sent_ok ->
                "ok;0"
            after
              5000 ->
                "error;timeout"
            end

        _ ->
          "error;closed"
      end

    {code, headers, body, s} = :stargate_plugin.serve_static_bin(page, h, s)
    headers = Map.put(headers, "Content-Type", "application/javascript")
    {code, headers, body, s}
  end


  def http(verb, path, q, h, _, s) do
    IO.inspect({verb, path, q, h})
  end
end

defmodule ConnWorker do
  use GenServer
  # last[poll
  # buf
  # if lastpoll > 30s drop

  def init(args) do
    host = :binary.bin_to_list(args.host)
    {:ok, socket} = :gen_tcp.connect(host, args.port, [:binary, {:active, true}])
    :erlang.send_after(30000, self(), :tick)
    {:ok, %{buf: "", socket: socket, lastpoll: :os.system_time(1000)}}
  end

  def handle_info(:tick, state) do
    if :os.system_time(1000) - state.lastpoll > 30000 do
      {:stop, :timeout}
    else
      :erlang.send_after(1000, self(), :tick)
      {:noreply, state}
    end
  end

  def handle_info({:tcp, socket, buff}, state) do
    IO.puts("got data #{inspect({socket, buff})}")
    {:noreply, %{state | buff: state.buff <> buff}}
  end

  def handle_info({:push_data, data, from}, state) do
    :gen_tcp.send(state.socket, data)
    send from, :sent_ok
    {:noreply, state}
  end

  def handle_info({:poll_data, from}, state) do
    send(from, {:data, state.buff})

    {:noreply, %{state | buff: "", lastpoll: :os.system_time()}}
  end
end
