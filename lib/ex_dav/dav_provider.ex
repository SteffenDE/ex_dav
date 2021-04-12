defmodule ExDav.DavProvider do
  @moduledoc """
  This module defines the basic callbacks for an ExDAV Dav Provider.
  """

  @callback read_only() :: boolean()

  @callback resolve(conn :: Plug.Conn.t()) :: ExDav.Resource.t()

  defmacro __using__(_) do
    quote do
      @behaviour ExDav.DavProvider

      def read_only, do: true

      defoverridable read_only: 0
    end
  end
end
