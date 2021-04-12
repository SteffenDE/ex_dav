use Mix.Config

config :plug, :validate_header_keys_during_test, false

config :ex_dav,
  http_server: [chunker: ExDav.HTTPChunkerMock]
