defmodule ExDavDemo.WebDAVServer do
  use Plug.Builder
  import Plug.BasicAuth

  plug(Plug.Logger)

  plug(:basic_auth, username: "demo", password: "demo")

  plug(ExDav.Plug,
    dav_provider: ExDav.FileSystemProvider,
    dav_provider_opts: [root: "/"]
  )
end
