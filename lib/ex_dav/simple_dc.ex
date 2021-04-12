defmodule ExDav.SimpleDC do
  use ExDav.DomainController

  @impl true
  def require_authentication(_conn, _realm) do
    true
  end

  @impl true
  def verify(_conn, _username, _password) do
    true
  end
end
