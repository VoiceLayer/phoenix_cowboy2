defmodule Phoenix.Endpoint.Cowboy2ReqHandler do

  def init(req, {server, opts} = state) do
    req = :cowboy_req.stream_reply(200, %{":status" => 200}, req)
    conn = Plug.Adapters.Cowboy2.Conn.conn(req)
    server.init(conn, opts)
  end
end
