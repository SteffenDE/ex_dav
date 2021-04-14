defmodule ExDav.DavResource do
  @moduledoc """
  Represents a DAV Resource (either a collection or a non-collection).

  Used as a consistent way for rendering the XML responses. See `ExDav.XMLHelpers`.
  """

  defstruct [
    :href,
    :props,
    :children
  ]
end
