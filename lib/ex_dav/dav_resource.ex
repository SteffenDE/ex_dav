defprotocol ExDav.Resource do
  @spec to_dav_struct(t) :: ExDav.DavResource.t()
  def to_dav_struct(ref)

  @spec get_content_length(t) :: non_neg_integer()
  def get_content_length(ref)

  @spec get_content_type(t) :: String.t()
  def get_content_type(ref)

  @spec get_display_name(t) :: String.t()
  def get_display_name(ref)

  @spec get_content(t, Keyword.t()) :: binary()
  def get_content(ref, opts)

  @spec get_stream(t, Keyword.t()) :: Enumerable.t()
  def get_stream(ref, opts)
end

defmodule ExDav.DavResource do
  @moduledoc """
  Represents a DAV Resource (either a collection or a non-collection)
  """

  defstruct [
    :href,
    :props,
    :children
  ]

  @type ref :: any()

  @callback supports_ranges() :: boolean()

  @callback supports_streaming() :: boolean()

  @callback supports_content_length() :: boolean()

  @callback resolve(path :: String.t()) :: ref()

  # needs ref

  @callback is_collection(ref()) :: boolean()

  @callback get_display_name(ref()) :: String.t()

  @callback get_members(ref()) :: [String.t()]

  @callback get_preferred_path(ref()) :: String.t()

  @callback get_creation_date(ref()) :: NaiveDateTime.t()

  @callback get_last_modified(ref()) :: NaiveDateTime.t()

  @callback get_content_length(ref()) :: non_neg_integer()

  @callback get_content_type(ref()) :: String.t()

  @callback get_content(ref(), opts :: Keyword.t()) :: binary()

  @callback get_stream(ref(), opts :: Keyword.t()) :: Enumerable.t()

  defmacro __using__(_) do
    quote do
      @behaviour ExDav.DavResource

      def supports_ranges(), do: false
      def supports_streaming(), do: false
      def supports_content_length(), do: false

      defoverridable supports_ranges: 0, supports_streaming: 0, supports_content_length: 0
    end
  end
end
