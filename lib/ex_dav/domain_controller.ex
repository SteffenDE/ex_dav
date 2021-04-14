defmodule ExDav.DomainController do
  @moduledoc """
  This module provides a behaviour for implementing an ExDav Domain Controller.
  """

  @type conn() :: Plug.Conn.t()
  @type realm() :: String.t()

  @doc """
  The realm returned in the WWW-Authenticate header. Could be dynamic, e.g. based on the path.
  """
  @callback domain_realm(conn) :: realm

  @doc """
  Used to check if we need to authenticate requests for this `realm`. Also receives the `conn`.
  """
  @callback require_authentication(conn, realm) :: boolean()

  @doc """
  Called with the `username` and `password`. Must return `true` to allow the request.

  Only called if `require_authentication/2` returned `true`.
  """
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
