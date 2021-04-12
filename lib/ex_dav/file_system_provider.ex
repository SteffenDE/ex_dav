defmodule ExDav.FileSystemProvider do
  use ExDav.DavProvider

  alias ExDav.FileSystemProvider.File, as: DavFile

  @impl true
  def resolve(conn) do
    conn.path_info
    |> Enum.join("/")
    |> URI.decode()
    |> DavFile.resolve()
  end

  def supports_ranges(), do: DavFile.supports_ranges()
  def supports_streaming(), do: DavFile.supports_streaming()
  def supports_content_length(), do: DavFile.supports_content_length()
end

defmodule ExDav.FileSystemProvider.File do
  defstruct [:fs_path, :path, :name, :stat]

  use ExDav.DavResource

  alias ExDav.FileSystemProvider.File, as: DavFile

  def root_path() do
    Application.get_env(:ex_dav, :file_system_provider, [])
    |> Keyword.get(:root, File.cwd!())
  end

  # defp hash_file(path) do
  #   File.stream!(path, [], 2048)
  #   |> Enum.reduce(:crypto.hash_init(:md5), fn line, acc -> :crypto.hash_update(acc, line) end)
  #   |> :crypto.hash_final()
  #   |> Base.encode16()
  # end

  @impl true
  def resolve(path) do
    fs_path = "#{root_path()}#{if String.starts_with?(path, "/"), do: path, else: "/" <> path}"

    with {:ok, stat} <- File.stat(fs_path) do
      %DavFile{
        fs_path: fs_path,
        path: path,
        name: List.last(String.split(fs_path, "/")),
        stat: stat
      }
    else
      other ->
        IO.inspect(other)
        nil
    end
  end

  @impl true
  def is_collection(%DavFile{stat: %{type: :directory}}), do: true
  def is_collection(_), do: false

  @impl true
  def get_members(%DavFile{fs_path: fs_path, path: path, stat: %{type: :directory}}) do
    Enum.map(File.ls!(fs_path), fn member ->
      fs_delimiter = if String.ends_with?(fs_path, "/"), do: "", else: "/"
      delimiter = if String.ends_with?(path, "/"), do: "", else: "/"
      new_fs_path = "#{fs_path}#{fs_delimiter}#{member}"
      new_path = "#{path}#{delimiter}#{member}"

      case File.stat(new_fs_path) do
        {:ok, stat} ->
          %DavFile{
            fs_path: new_fs_path,
            path: new_path,
            name: List.last(String.split(new_fs_path, "/")),
            stat: stat
          }

        _other ->
          nil
      end
    end)
    |> Enum.filter(fn i -> not is_nil(i) end)
  end

  @impl true
  def get_display_name(%DavFile{name: name}), do: name

  @impl true
  def get_creation_date(%DavFile{stat: %{ctime: ctime}}) do
    NaiveDateTime.from_erl!(ctime)
  end

  @impl true
  def get_last_modified(%DavFile{stat: %{mtime: mtime}}) do
    NaiveDateTime.from_erl!(mtime)
  end

  @impl true
  def get_preferred_path(%DavFile{path: ""}), do: "/"

  def get_preferred_path(%DavFile{path: path, stat: %{type: type}}) do
    path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"

    case type do
      :directory -> if String.ends_with?(path, "/"), do: path, else: "#{path}/"
      _ -> path
    end
  end

  @impl true
  def get_content_length(%DavFile{stat: %{size: size}}), do: size

  @impl true
  def get_content_type(%DavFile{stat: %{type: :directory}}) do
    "application/x-directory"
  end

  def get_content_type(%DavFile{name: name}) do
    name
    |> String.split(".")
    |> List.last()
    |> MIME.type()
  end

  @impl true
  def supports_streaming(), do: true

  @impl true
  def supports_ranges(), do: true

  @impl true
  def supports_content_length(), do: true

  @impl true
  def get_content(%DavFile{fs_path: path}, opts) do
    range = Keyword.get(opts, :range)

    case range do
      nil ->
        File.read!(path)

      {range_start, range_end} ->
        io = File.open!(path)
        :file.position(io, {:bof, range_start})
        size = range_end - range_start + 1
        res = :file.read(io, size)
        File.close(io)
        res
    end
  end

  @impl true
  def get_stream(%DavFile{fs_path: path}, opts) do
    range = Keyword.get(opts, :range)

    case range do
      nil ->
        File.stream!(path, [], 1024 * 1024 * 8)

      {range_start, range_end} ->
        size = range_end - range_start + 1
        ExDav.FileSystemProvider.IOHelpers.stream!(path, range_start, size)
    end
  end
end

defimpl ExDav.Resource, for: ExDav.FileSystemProvider.File do
  alias ExDav.FileSystemProvider.File, as: DavFile

  defp map_ref(nil, _), do: nil

  defp map_ref(ref, depth) do
    if DavFile.is_collection(ref) do
      %ExDav.DavResource{
        href: DavFile.get_preferred_path(ref) |> URI.encode(),
        props: %{
          resourcetype: "<collection/>",
          creationdate:
            DavFile.get_creation_date(ref) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT"),
          displayname: DavFile.get_display_name(ref),
          getcontentlength: DavFile.get_content_length(ref),
          getcontenttype: DavFile.get_content_type(ref),
          getlastmodified:
            DavFile.get_last_modified(ref) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
        },
        children:
          if depth == 0 do
            DavFile.get_members(ref)
            |> Enum.map(fn mem -> map_ref(mem, depth + 1) end)
          else
            []
          end
      }
    else
      %ExDav.DavResource{
        href: DavFile.get_preferred_path(ref) |> URI.encode(),
        props: %{
          creationdate:
            DavFile.get_creation_date(ref) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT"),
          displayname: DavFile.get_display_name(ref),
          getcontentlength: DavFile.get_content_length(ref),
          getcontenttype: DavFile.get_content_type(ref),
          getlastmodified:
            DavFile.get_last_modified(ref) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
        },
        children: nil
      }
    end
  end

  def to_dav_struct(ref) do
    map_ref(ref, 0)
  end

  def get_content_length(ref), do: DavFile.get_content_length(ref)

  def get_content_type(ref), do: DavFile.get_content_type(ref)

  def get_display_name(ref), do: DavFile.get_display_name(ref)

  def get_content(ref, opts), do: DavFile.get_content(ref, opts)

  def get_stream(ref, opts), do: DavFile.get_stream(ref, opts)
end

defmodule ExDav.FileSystemProvider.IOHelpers do
  @chunk_size 8 * 1024 * 1024

  @doc """
  Streams length bytes from offset of the specified file. Optionally accepts a chunk size.
  """
  def stream!(path, offset, length, chunk_size \\ @chunk_size) do
    Stream.resource(
      fn ->
        io = File.open!(path)
        :file.position(io, {:bof, offset})
        # IO.inspect(io, label: "io")
        {0, io}
      end,
      fn {cur, io} ->
        # IO.inspect(cur, label: "current")
        if cur >= length do
          {:halt, {cur, io}}
        else
          case :file.read(io, min(length - cur, chunk_size)) do
            # |> IO.inspect(label: "res")
            {:ok, data} -> {[data], {cur + chunk_size, io}}
            # |> IO.inspect(label: "halt")
            _ -> {:halt, {cur, io}}
          end
        end
      end,
      fn {_, io} -> File.close(io) end
    )
  end
end
