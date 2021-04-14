Mox.defmock(ExDav.HTTPChunkerMock, for: ExDav.HTTPChunker)
Application.put_env(:ex_dav, :chunker, ExDav.HTTPChunkerMock)
