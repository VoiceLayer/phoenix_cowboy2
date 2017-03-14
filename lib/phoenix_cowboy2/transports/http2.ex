defmodule Phoenix.Transports.HTTP2 do
  @behaviour Phoenix.Socket.Transport

  import Plug.Conn, only: [fetch_query_params: 1, send_resp: 3]

  alias Phoenix.Socket.Transport

  require Logger

  def default_config() do
    [serializer: Phoenix.Transports.WebSocketSerializer,
     timeout: 60_000,
     transport_log: false]
  end

  ## Callbacks

  def init(conn, {endpoint, handler, transport}) do
    {_, opts} = handler.__transport__(transport)

    conn =
      conn
      |> code_reload(opts, endpoint)
      |> fetch_query_params()
      |> Transport.transport_log(opts[:transport_log])
      |> Transport.force_ssl(handler, endpoint, opts)
      |> Transport.check_origin(handler, endpoint, opts)

    params     = conn.params
    serializer = Keyword.fetch!(opts, :serializer)

    case Transport.connect(endpoint, handler, transport, __MODULE__, serializer, params) do
      {:ok, socket} ->
        if socket.id, do: socket.endpoint.subscribe(socket.id, link: true)
        loop(conn, %{ref: nil, serializer: serializer, channels: %{}, channels_inverse: %{}, socket: socket})
      :error ->
        send_resp(conn, 403, "")
        {:error, conn}
    end
  end

  def loop(conn, state) do
    {_, req} = conn.adapter
    ref =
      if state.ref do
        state.ref
      else
        ref = make_ref()
        send(req.pid, {{req.pid, req.streamid}, {:read_body, ref, 1, 30_000}})
        ref
      end
    state = %{state | ref: ref}
    receive do
      {:request_body, ^ref, :fin, req_body} ->
        handle_req_body(conn, req_body, state)
      {:request_body, ^ref, :nofin, req_body} ->
        {:ok, state} = handle_req_body(conn, req_body, state)
        state = %{state | ref: nil}
        loop(conn, state)
      {:socket_push, _encoding, _payload} = push ->
        format_reply(push, conn)
        loop(conn, state)
      other ->
        Logger.warn("ignored message #{inspect other}")
        loop(conn, state)
    end
  end

  defp handle_req_body(conn, "", state), do: {:ok, state}
  defp handle_req_body(conn, payload, state) do
    msg = state.serializer.decode!(payload, [])
    case Transport.dispatch(msg, state.channels, state.socket) do
      :noreply ->
        {:ok, state}
      {:reply, reply_msg} ->
        encode_reply(reply_msg, state, conn)
      {:joined, channel_pid, reply_msg} ->
        encode_reply(reply_msg, put(state, msg.topic, msg.ref, channel_pid), conn)
      {:error, _reason, error_reply_msg} ->
        encode_reply(error_reply_msg, state, conn)
    end
  end

  defp code_reload(conn, opts, endpoint) do
    reload? = Keyword.get(opts, :code_reloader, endpoint.config(:code_reloader))
    if reload?, do: Phoenix.CodeReloader.reload!(endpoint)

    conn
  end

  defp encode_reply(reply, state, conn) do
    format_reply(state.serializer.encode!(reply), conn)
    {:ok, state}
  end

  defp format_reply({:socket_push, encoding, encoded_payload}, conn) do
    {_, req} = conn.adapter
    :cowboy_req.stream_body(encoded_payload, :nofin, req)
  end

  defp put(state, topic, join_ref, channel_pid) do
    %{state | channels: Map.put(state.channels, topic, channel_pid),
      channels_inverse: Map.put(state.channels_inverse, channel_pid, {topic, join_ref})}
  end

  defp delete(state, topic, channel_pid) do
    case Map.fetch(state.channels, topic) do
      {:ok, ^channel_pid} ->
        %{state | channels: Map.delete(state.channels, topic),
          channels_inverse: Map.delete(state.channels_inverse, channel_pid)}
      {:ok, _newer_pid} ->
        %{state | channels_inverse: Map.delete(state.channels_inverse, channel_pid)}
    end
  end
end
