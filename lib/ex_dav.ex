defmodule ExDav do
  @moduledoc """
  Documentation for `ExDav`.
  """

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Plug.Cowboy, scheme: :http, plug: ExDav.HTTPServer, port: 5000}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Hello world.

  ## Examples

      iex> ExDav.hello()
      :world

  """
  def hello do
    :world
  end
end
