defmodule ExDav.DomainController do
  @moduledoc """
  This module provides a behaviour for implementing a ExDav Domain Controller.
  """

  @type conn() :: Plug.Conn.t()
  @type realm() :: String.t()

  @callback domain_realm(conn) :: realm

  @callback require_authentication(conn, realm) :: boolean()

  @callback verify(conn, username :: String.t(), password :: String.t()) :: boolean()

  defmacro __using__(_) do
    quote do
      @behaviour ExDav.DomainController

      def domain_realm(_), do: "WebDAV"

      def require_authentication(_, _), do: false

      def verify(_, _, _), do: raise("not implemented")

      defoverridable domain_realm: 1, require_authentication: 2, verify: 3
    end
  end
end
