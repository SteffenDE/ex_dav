defmodule ExDavDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: ExDavDemo.Worker.start_link(arg)
      # {ExDavDemo.Worker, arg}
      {Plug.Cowboy,
       scheme: :http,
       plug:
         {ExDav.Plug,
          [
            dav_provider: ExDav.FileSystemProvider,
            dav_provider_opts: [root: "/"],
            domain_controller: ExDav.SimpleDC
          ]},
       port: 5000}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExDavDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
