defmodule ExDav.AuthHelpers do
  import Plug.Conn

  defp verify_auth(conn, dc) do
    if dc.require_authentication(conn, conn.assigns.realm) do
      handle_auth(conn, dc)
    else
      conn
    end
  end

  defp handle_auth(conn, dc) do
    with {user, pass} <- parse_basic_auth(conn) do
      if dc.verify(conn, user, pass) do
        conn
        |> assign(:dav_username, user)
      else
        conn
        |> send_resp(403, "Unauthorized")
        |> halt()
      end
    else
      :error ->
        conn
        |> put_resp_header("WWW-Authenticate", "Basic realm=#{conn.assigns.realm}")
        |> send_resp(401, "Authentication required")
        |> halt()
    end
  end

  def parse_basic_auth(conn) do
    with ["Basic " <> encoded_user_and_pass] <- get_req_header(conn, "authorization"),
         {:ok, decoded_user_and_pass} <- Base.decode64(encoded_user_and_pass),
         [user, pass] <- :binary.split(decoded_user_and_pass, ":") do
      {user, pass}
    else
      _ -> :error
    end
  end

  def do_auth(conn, dc) do
    if is_nil(dc) do
      conn
    else
      verify_auth(conn, dc)
    end
  end

  # Plug

  def authenticate(conn, dc) do
    conn
    |> assign(:realm, dc.domain_realm(conn))
    |> do_auth(dc)
  end
end
