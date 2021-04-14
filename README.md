# ExDav

[![Build Status](https://gitlab.com/steffend/ex_dav/badges/main/pipeline.svg)](https://gitlab.com/steffend/ex_dav/)
[![Coverage](https://gitlab.com/steffend/ex_dav/badges/main/coverage.svg)](https://gitlab.com/steffend/ex_dav/)

**Warning:** work in progress! currently only working with read-only shares.

ExDav is a library that implements an extendable [WebDAV](https://tools.ietf.org/html/rfc4918) server in Elixir using Plug.
This project is heavily inspired by the great Python [wsgidav](https://github.com/mar10/wsgidav) app.

As this is a library, ExDav does not come with an included HTTP server. A demo project using ExDav with [plug_cowboy](https://github.com/elixir-plug/plug_cowboy) is provided in the `demo` subdirectory.

## Installation

This package is currently **not** [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_dav` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_dav, github: "SteffenDE/ex_dav"}
  ]
end
```
