defmodule ExDav.FileSystemProvider.File do
  defstruct [:fs_path, :path, :name, :stat]
end

defmodule ExDav.FileSystemProvider do
  use ExDav.DavProvider

  alias ExDav.FileSystemProvider.File, as: DavFile

  @impl true
  def read_only(), do: false

  @impl true
  def resolve(path, opts \\ []) when is_list(opts) do
    root_path =
      Keyword.get(opts, :root, File.cwd!())
      |> String.replace_trailing("/", "")

    fs_path = "#{root_path}#{if String.starts_with?(path, "/"), do: path, else: "/" <> path}"

    with {:ok, stat} <- File.stat(fs_path) do
      %DavFile{
        fs_path: fs_path,
        path: path,
        name: List.last(String.split(fs_path, "/")),
        stat: stat
      }
    else
      _other ->
        nil
    end
  end

  @impl true
  def supports_streaming(_), do: true

  @impl true
  def supports_streaming_uploads(_), do: true

  @impl true
  def supports_ranges(_), do: true

  @impl true
  def supports_content_length(_), do: true

  @impl true
  def supports_etag(_), do: true

  @impl true
  def supports_recursive_move(), do: true

  @impl true
  def supports_recursive_delete(), do: true

  @impl true
  def is_collection(%DavFile{stat: %{type: :directory}}), do: true
  def is_collection(_), do: false

  @impl true
  def get_display_name(%DavFile{name: name}), do: name

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
  def get_preferred_path(%DavFile{path: ""}), do: "/"

  def get_preferred_path(%DavFile{path: path, stat: %{type: type}}) do
    path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"

    case type do
      :directory -> if String.ends_with?(path, "/"), do: path, else: "#{path}/"
      _ -> path
    end
  end

  @impl true
  def get_creation_date(%DavFile{stat: %{ctime: ctime}}) do
    NaiveDateTime.from_erl!(ctime)
  end

  @impl true
  def get_last_modified(%DavFile{stat: %{mtime: mtime}}) do
    NaiveDateTime.from_erl!(mtime)
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
  def get_etag(%DavFile{fs_path: path, stat: %{mtime: mtime, size: size}}) do
    "#{:erlang.phash2(path)}-#{:erlang.phash2(mtime)}-#{:erlang.phash2(size)}"
  end

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

  @impl true
  def create_empty_resource(%DavFile{fs_path: path}, name) do
    File.touch("#{path}/#{name}")
  end

  @impl true
  def create_collection(%DavFile{fs_path: path}, name) do
    File.mkdir("#{path}/#{name}")
  end

  @impl true
  def write_stream(%DavFile{fs_path: path}, stream) do
    output = File.stream!(path, [], 1024 * 1024 * 8)

    Stream.into(stream, output)
    |> Stream.run()
  end

  @impl true
  def copy(%DavFile{fs_path: fs_path, path: dav_path}, dest) do
    root_path = String.trim_leading(fs_path, dav_path) <> "/"
    dest_fs_path = "#{root_path}#{if String.starts_with?(dest, "/"), do: dest, else: "/" <> dest}"

    with {:ok, _} <- File.copy(fs_path, dest_fs_path) do
      :ok
    end
  end

  @impl true
  def delete(%DavFile{fs_path: fs_path, stat: %{type: :regular}}) do
    File.rm(fs_path)
  end

  def delete(%DavFile{fs_path: fs_path, stat: %{type: :directory}}) do
    with {:ok, _deleted} <- File.rm_rf(fs_path) do
      :ok
    end
  end

  @impl true
  def move_recursive(%DavFile{fs_path: fs_path, path: dav_path}, dest) do
    root_path = String.trim_leading(fs_path, dav_path) <> "/"
    dest_fs_path = "#{root_path}#{if String.starts_with?(dest, "/"), do: dest, else: "/" <> dest}"

    File.rename(fs_path, dest_fs_path)
  end
end

defmodule ExDav.FileSystemProvider.IOHelpers do
  @chunk_size 8 * 1024 * 1024

  @doc """
  Streams length bytes from offset of the specified file. Optionally accepts a chunk size.
  """
  def stream!(path, offset, length, chunk_size \\ @chunk_size) do
    Stream.resource(
      fn ->
        io = File.open!(path, [:read, :binary, :raw])
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
