defmodule ExDav.DavView do
  import Plug.Conn

  def render_tree(conn, tree, code \\ 200) do
    response =
      tree
      |> Saxy.encode!()

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(code, ~s(<?xml version="1.0" encoding="utf-8" ?>) <> response)
  end
end
