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

  # Available Functionality

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
  Defines whether the resource upload is streamed.
  If `true` the provider MUST implement the `write_stream/2` function.

  By default, always returns `false`.
  We strongly recommend providers to implement this, especially when dealing with big files.
  """
  @callback supports_streaming_uploads(ref()) :: boolean()

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
  Defines whether delete() can be called on non-empty collections.

  By default, returns false.
  """
  @callback supports_recursive_delete() :: boolean()

  @doc """
  Defines whether move() can be called on non-empty collections.
  When false a move is handled by copying (and deleting) each member.

  By default, returns false.
  """
  @callback supports_recursive_move() :: boolean()

  # Basic Properties

  @doc """
  Used to set the href location of a resource. Resources can have many locations, as paths are case sensitive.
  This method should return the preferred path, e.g. a downcased version of the path.

  Providers SHOULD implement this callback.
  """
  @callback get_preferred_path(ref()) :: String.t()

  @doc """
  Used to set the `displayname` property.

  By default, returns the last path segment.
  """
  @callback get_display_name(ref()) :: String.t()

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

  # Collections

  @doc """
  Used to check if the opaque reference is a collection.
  Providers MUST implement this callback.
  """
  @callback is_collection(ref()) :: boolean()

  @doc """
  Used to get the members of a collection.
  Only called for collections.

  Providers MUST implement this callback if they server any collection.
  """
  @callback get_members(ref()) :: [String.t()]

  # Content

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

  # Read-Write

  @doc """
  Creates a new empty resource as a member of the collection specified by `ref()`.

  Used when creating new files using PUT.
  """
  @callback create_empty_resource(ref(), name :: String.t()) :: :ok | {:error, reason :: any()}

  @doc """
  Create a new collection as member of the specified `ref()`.

  We make sure that the `ref()` is an existing collection.

  Providers MUST implement this callback if `read_only/0` is `false`.
  """
  @callback create_collection(ref(), name :: String.t()) :: :ok | {:error, reason :: any()}

  @doc """
  Lazily uploads the request body to this resource.

  Only called when `supports_streaming_uploads/1` returns `true`.
  """
  @callback write_stream(ref(), stream :: Stream.t()) :: :ok | {:error, reason :: any()}

  @doc """
  Writes the specified binary into this resource.

  Only called when `supports_streaming_uploads/1` returns `false`.
  """
  @callback write(ref(), binary()) :: :ok | {:error, reason :: any()}

  @doc """
  Deletes the resource specified by `ref()`.

  If `supports_recursive_delete/0` is false, and this is a collection,
  all members have already been deleted.

  Providers MUST implement this callback if `read_only/0` is `false`.
  """
  @callback delete(ref()) :: :ok | {:error, list()}

  @doc """
  Copies the specified resource to the destination path.
  """
  @callback copy(ref(), dest_path :: String.t()) :: :ok | {:error, reason :: any()}

  @doc """
  Moves the specified resource to the destination path.

  Only called when `supports_recursive_move/0` returns `true`.
  Otherwise, moving is implemented by copying and deleting.
  """
  @callback move_recursive(ref(), dest_path :: String.t()) :: :ok | {:error, reason :: any()}

  defmacro __using__(_) do
    module = __CALLER__.module

    quote do
      @behaviour ExDav.DavProvider

      @impl true
      def exists(path, opts), do: not is_nil(resolve(path, opts))

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
      def read_only, do: true

      @impl true
      def supports_ranges(_), do: false

      @impl true
      def supports_streaming(_), do: false

      @impl true
      def supports_streaming_uploads(_), do: false

      @impl true
      def supports_content_length(_), do: false

      @impl true
      def supports_etag(_), do: false

      @impl true
      def supports_recursive_delete(), do: false

      @impl true
      def supports_recursive_move(), do: false

      @impl true
      def get_display_name(ref) do
        path = unquote(module).get_preferred_path(ref)
        List.last(String.split(path, "/"))
      end

      @impl true
      def get_creation_date(_), do: nil

      @impl true
      def get_last_modified(_), do: nil

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

      @impl true
      def get_etag(_), do: nil

      @impl true
      def create_empty_resource(_, _) do
        raise "oops! Seems like you forgot implementing create_empty_resource/2"
      end

      @impl true
      def create_collection(_, _) do
        raise "oops! Seems like you forgot implementing create_collection/2"
      end

      @impl true
      def write_stream(_, _) do
        raise "oops! Seems like you forgot implementing write_stream/2"
      end

      @impl true
      def write(_, _) do
        raise "oops! Seems like you forgot implementing write/2"
      end

      @impl true
      def delete(_) do
        raise "oops! Seems like you forgot implementing delete/1"
      end

      @impl true
      def copy(_, _) do
        raise "oops! Seems like you forgot implementing copy/2"
      end

      @impl true
      def move_recursive(_, _) do
        raise "oops! Seems like you forgot implementing move_recursive/2"
      end

      defoverridable ExDav.DavProvider
    end
  end
end
