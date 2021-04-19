defmodule ExDav.DavProvider do
  @moduledoc """
  This module defines the basic callbacks for an ExDAV Dav Provider.
  """

  @type ref :: any()

  @doc """
  The main function that is called for any incoming request. Used to resolve the WebDAV resource.

  Returns an opaque identifier that is passed to the other callbacks.
  """
  @callback resolve(path :: String.t(), opts :: list()) :: ref()

  @doc """
  The function checks if a resource exists for the given path.

  By default calls resolve and checks if the return values is not nil.
  Should be replaced by a more efficient implementation.
  """
  @callback exists(path :: String.t(), opts :: list()) :: boolean()

  @doc """
  Used to format the resource into the `ExDav.DavResource` struct.
  A default implementation is provided when using this module.
  """
  @callback to_dav_struct(ref()) :: ExDav.DavResource.t()

  @doc """
  Defines whether the provider is read-only. Currently we only support read-only providers.

  By default, always returns `false`.
  """
  @callback read_only() :: boolean()

  @doc """
  Defines whether the resource supports range requests.
  If `true` the provider MUST handle the range option in `get_content/2` / `get_stream/2`.

  By default, always returns `false`.
  """
  @callback supports_ranges(ref()) :: boolean()

  @doc """
  Defines whether the resource is streamed.
  If `true` the provider MUST implement the `get_stream/2` function.

  By default, always returns `false`.
  """
  @callback supports_streaming(ref()) :: boolean()

  @doc """
  Defines whether the resource supports the Content-Length header.
  If `true` the provider MUST implement the `get_content_length/1` function.
  If `false` the response in sent without a Content-Length header in chunked encoding.

  By default, always returns `false`.
  """
  @callback supports_content_length(ref()) :: boolean()

  @doc """
  Defines whether the resource supports the Etag header.
  If `true` the provider MUST implement the `get_etag/1` function.

  By default, always returns `false`.
  """
  @callback supports_etag(ref()) :: boolean()

  @doc """
  Used to check if the opaque reference is a collection.
  Providers MUST implement this callback.
  """
  @callback is_collection(ref()) :: boolean()

  @doc """
  Used to set the `displayname` property.

  By default, returns the last path segment.
  """
  @callback get_display_name(ref()) :: String.t()

  @doc """
  Used to get the members of a collection.
  Only called for collections.

  Providers MUST implement this callback if they server any collection.
  """
  @callback get_members(ref()) :: [String.t()]

  @doc """
  Used to set the href location of a resource. Resources can have many locations, as paths are case sensitive.
  This method should return the preferred path, e.g. a downcased version of the path.

  Providers SHOULD implement this callback.
  """
  @callback get_preferred_path(ref()) :: String.t()

  @doc """
  Used to get the creation date.

  Providers SHOULD implement this callback, especially for non-collections.
  """
  @callback get_creation_date(ref()) :: NaiveDateTime.t()

  @doc """
  Used to get the modification date.

  Providers SHOULD implement this callback, especially for non-collections.
  """
  @callback get_last_modified(ref()) :: NaiveDateTime.t()

  @doc """
  Used to get the Content-Length header.

  Providers SHOULD implement this callback, especially for non-collections.
  """
  @callback get_content_length(ref()) :: non_neg_integer() | nil

  @doc """
  Used to get the Content-Type header.

  Providers SHOULD implement this callback, especially for non-collections.
  Defaults to `application/octet-stream`.
  """
  @callback get_content_type(ref()) :: String.t()

  @doc """
  Used to get the Etag header.

  Providers SHOULD implement this callback, especially for non-collections.
  """
  @callback get_etag(ref()) :: String.t() | nil

  @doc """
  Used to get the response body for GET requests.

  Providers MUST implement this callback unless `supports_streaming/1` is `true` for the resource.
  """
  @callback get_content(ref(), opts :: Keyword.t()) :: binary()

  @doc """
  Used to get the response body for GET requests in a memory efficient way.

  Providers MUST only implement this callback if `supports_streaming/1` is `true` for the resource.
  Providers SHOULD implement this callback when serving large files.
  """
  @callback get_stream(ref(), opts :: Keyword.t()) :: Enumerable.t()

  @doc """
  Create a new collection as member of the specified `ref()`.

  We make sure that the `ref()` is an existing collection.

  Providers MUST implement this callback if `read_only/0` is `false`.
  """
  @callback create_collection(ref(), name :: String.t()) :: :ok | {:error, any()}

  defmacro __using__(_) do
    module = __CALLER__.module

    quote do
      @behaviour ExDav.DavProvider

      @impl true
      def exists(path, opts), do: not is_nil(resolve(path, opts))

      @impl true
      def read_only, do: true

      @impl true
      def supports_ranges(_), do: false

      @impl true
      def supports_streaming(_), do: false

      @impl true
      def supports_content_length(_), do: false

      @impl true
      def supports_etag(_), do: false

      @impl true
      def get_display_name(ref) do
        path = unquote(module).get_preferred_path(ref)
        List.last(String.split(path, "/"))
      end

      @impl true
      def get_etag(_), do: nil

      @impl true
      def get_content_length(_), do: nil

      @impl true
      def get_content_type(ref) do
        if unquote(module).is_collection(ref) do
          "application/x-directory"
        else
          "application/octet-stream"
        end
      end

      defp map_ref(nil, _), do: nil

      defp map_ref(ref, depth) do
        props = %{
          creationdate:
            unquote(module).get_creation_date(ref)
            |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT"),
          displayname: "<![CDATA[#{unquote(module).get_display_name(ref)}]]>",
          getcontentlength: unquote(module).get_content_length(ref),
          getcontenttype: unquote(module).get_content_type(ref),
          getetag: unquote(module).get_etag(ref),
          getlastmodified:
            unquote(module).get_last_modified(ref)
            |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
        }

        if unquote(module).is_collection(ref) do
          props = Map.put(props, :resourcetype, "<collection/>")

          %ExDav.DavResource{
            href: unquote(module).get_preferred_path(ref) |> URI.encode(),
            props: props,
            children:
              if depth == 0 do
                unquote(module).get_members(ref)
                |> Enum.map(fn mem -> map_ref(mem, depth + 1) end)
              else
                []
              end
          }
        else
          %ExDav.DavResource{
            href: unquote(module).get_preferred_path(ref) |> URI.encode(),
            props: props,
            children: nil
          }
        end
      end

      @impl true
      def to_dav_struct(ref) do
        map_ref(ref, 0)
      end

      @impl true
      def create_collection(_ref, _name), do: {:error, :not_implemented}

      defoverridable ExDav.DavProvider
    end
  end
end
