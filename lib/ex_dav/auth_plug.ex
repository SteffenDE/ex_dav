defmodule ExDav.AuthPlug do
  import Plug.Conn

  def domain_controller() do
    Application.get_env(:ex_dav, :domain_controller, ExDav.SimpleDC)
  end

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

  def authenticate(conn) do
    dc = domain_controller()

    if is_nil(dc) do
      conn
    else
      verify_auth(conn, dc)
    end
  end

  # Plug

  def init(_), do: []

  def call(conn, _opts) do
    conn
    |> assign(:realm, domain_controller().domain_realm(conn))
    |> authenticate()
  end
end
