defmodule ExDav.HTTPChunker do
  @callback chunk_to_conn(Plug.Conn.t(), any()) :: {:ok, Plug.Conn.t()} | {:error, any()}
  def chunk_to_conn(conn, current_chunk) do
    Plug.Conn.chunk(conn, current_chunk)
  end
end

defmodule ExDav.Plug do
  use Plug.Builder

  require Logger

  import ExDav.XMLHelpers

  # set for testing @ test/support/mocks.ex
  @chunker Application.get_env(:ex_dav, :chunker, ExDav.HTTPChunker)

  plug(:assign_handler, builder_opts())
  plug(:check_readonly)
  plug(:assign_depth)
  plug(:disallow_infinity)
  plug(:tame_macos)
  plug(:dispatch)

  def assign_handler(conn, opts) do
    dav_provider = Keyword.get(opts, :dav_provider, ExDav.FileSystemProvider)
    dav_provider_opts = Keyword.get(opts, :dav_provider_opts, [])
    lock_manager = Keyword.get(opts, :lock_manager)
    lock_manager_opts = Keyword.get(opts, :lock_manager_opts, [])

    dav_path =
      conn.path_info
      |> Enum.join("/")
      |> URI.decode()
      |> String.replace_trailing("/", "")

    dav_name =
      List.last(conn.path_info) ||
        ""
        |> URI.decode()

    conn
    |> assign(:dav_provider, {dav_provider, dav_provider_opts})
    |> assign(:lock_manager, {lock_manager, lock_manager_opts})
    |> assign(:dav_path, "/#{dav_path}")
    |> assign(:dav_name, dav_name)
  end

  # read only?

  defp send_forbidden_if_write(conn, false), do: conn

  defp send_forbidden_if_write(conn = %Plug.Conn{method: method}, true)
       when method in [
              "POST",
              "PUT",
              "MKCOL",
              "PROPPATCH",
              "LOCK",
              "UNLOCK",
              "DELETE",
              "COPY",
              "MOVE"
            ] do
    conn
    |> send_resp(403, "This server is read only")
    |> halt()
  end

  defp send_forbidden_if_write(conn, true), do: conn

  defp check_readonly(conn = %{assigns: %{dav_provider: {dav_provider, _}}}, _opts) do
    send_forbidden_if_write(conn, dav_provider.read_only())
  end

  # depth

  defp assign_depth(conn, _opts) do
    case get_req_header(conn, "depth") do
      ["0"] ->
        assign(conn, :depth, 0)

      ["1"] ->
        assign(conn, :depth, 1)

      ["infinity"] ->
        assign(conn, :depth, :infinity)

      [] ->
        assign(conn, :depth, :infinity)

      _other ->
        conn
        |> put_status(400)
        |> send_resp(400, "Depth Header must be one of 0, 1, infinity")
        |> halt()
    end
  end

  defp disallow_infinity(
         conn = %Plug.Conn{method: "PROPFIND", assigns: %{depth: :infinity}},
         _opts
       ) do
    tree =
      Saxy.XML.element("error", [{"xmlns", "DAV:"}], [
        Saxy.XML.element("propfind-finite-depth", [], [])
      ])

    ExDav.DavView.render_tree(conn, tree, 403)
    |> halt()
  end

  defp disallow_infinity(conn, _opts), do: conn

  # tame mac os finder requests
  # see: https://gist.github.com/jens1101/9f3faa6c2dae23537257f1c3d0afdfdf
  defp tame_macos(conn, _opts) do
    cond do
      conn.request_path =~ ~r/\.(_.*|DS_Store|Spotlight-V100|TemporaryItems|Trashes|hidden)$/ ->
        case conn.method do
          "PUT" -> send_resp(conn, 403, "Forbidden") |> halt()
          _ -> send_resp(conn, 404, "Not Found") |> halt()
        end

      conn.request_path =~ ~r/\.metadata_never_index$/ ->
        send_resp(conn, 200, "") |> halt()

      true ->
        conn
    end
  end

  # sending files

  defp maybe_set_range_response(conn, provider, resource, true) do
    content_length = provider.get_content_length(resource)

    {conn, 200, content_length, 0, content_length - 1}
  end

  defp maybe_set_range_response(conn, provider, resource, false) do
    is_range_request = not Enum.empty?(get_req_header(conn, "range"))
    file_length = provider.get_content_length(resource)

    [range_start, range_end] =
      if is_range_request do
        [rn] = get_req_header(conn, "range")

        res = Regex.run(~r/bytes=([0-9]+)-([0-9]+)?/, rn)
        default_end = Integer.to_string(file_length - 1)

        {range_start, _} = res |> Enum.at(1) |> Integer.parse()
        {range_end, _} = res |> Enum.at(2, default_end) |> Integer.parse()

        [range_start, range_end]
      else
        [0, file_length - 1]
      end

    content_length = range_end - range_start + 1

    conn =
      conn
      |> Plug.Conn.put_resp_header("content-length", Integer.to_string(content_length))
      |> Plug.Conn.put_resp_header(
        "content-range",
        "bytes #{range_start}-#{range_end}/#{file_length}"
      )

    {conn, if(is_range_request, do: 206, else: 200), content_length, range_start, range_end}
  end

  defp send_resource(conn = %{assigns: %{dav_provider: {dav_provider, _}}}, resource, opts) do
    head = Keyword.get(opts, :head, false)
    is_range_request = not Enum.empty?(get_req_header(conn, "range"))
    supports_ranges = dav_provider.supports_ranges(resource)
    supports_streaming = dav_provider.supports_streaming(resource)
    supports_content_length = dav_provider.supports_content_length(resource)
    content_length = dav_provider.get_content_length(resource)
    content_type = dav_provider.get_content_type(resource)
    display_name = dav_provider.get_display_name(resource)

    ignore_ranges =
      not is_range_request or not supports_ranges or not supports_content_length or
        content_length == 0

    {conn, code, content_length, range_start, range_end} =
      maybe_set_range_response(conn, dav_provider, resource, ignore_ranges)

    conn =
      conn
      |> Plug.Conn.put_resp_content_type(content_type)
      |> Plug.Conn.put_resp_header("content-length", Integer.to_string(content_length))
      |> Plug.Conn.put_resp_header("accept-ranges", "bytes")
      |> Plug.Conn.put_resp_header("content-disposition", ~s(inline; filename="#{display_name}"))
      |> Plug.Conn.send_chunked(code)

    cond do
      head ->
        {:ok, conn} = @chunker.chunk_to_conn(conn, "")
        conn

      true ->
        if supports_streaming do
          dav_provider.get_stream(resource, range: {range_start, range_end})
          |> Enum.reduce_while(conn, fn chunk, conn ->
            case @chunker.chunk_to_conn(conn, chunk) do
              {:ok, conn} ->
                {:cont, conn}

              {:error, :closed} ->
                # IO.puts("error")
                {:halt, conn}

              {:error, other} ->
                Logger.error("chunking failed with #{inspect(other)}")
                {:halt, conn}
            end
          end)
        else
          {:ok, conn} =
            @chunker.chunk_to_conn(
              conn,
              dav_provider.get_content(resource, range: {range_start, range_end})
            )

          conn
        end
    end
  end

  # request handlers

  defp get_prefix(conn) do
    case Enum.join(conn.script_name, "/") do
      "" -> ""
      path -> "/#{path}"
    end
  end

  defp get_propstat(%ExDav.DavResource{} = resource, opts \\ []) do
    prop(resource, opts)
    |> Enum.map(fn {props, status} -> propstat(props, status) end)
  end

  defp handle_allprop(conn = %{assigns: %{depth: depth}}, dav_resource) do
    responses =
      cond do
        is_nil(dav_resource.children) or depth == 0 ->
          [response([href(get_prefix(conn) <> dav_resource.href) | get_propstat(dav_resource)])]

        true ->
          [
            response([href(get_prefix(conn) <> dav_resource.href) | get_propstat(dav_resource)])
            | Enum.map(dav_resource.children, fn child ->
                response([href(get_prefix(conn) <> child.href) | get_propstat(child)])
              end)
          ]
      end

    tree = multistatus(responses)

    ExDav.DavView.render_tree(conn, tree)
  end

  defp handle_propname(conn = %{assigns: %{depth: depth}}, dav_resource) do
    responses =
      cond do
        is_nil(dav_resource.children) or depth == 0 ->
          [
            response([
              href(get_prefix(conn) <> dav_resource.href)
              | get_propstat(dav_resource, values: false)
            ])
          ]

        true ->
          [
            response([
              href(get_prefix(conn) <> dav_resource.href)
              | get_propstat(dav_resource, values: false)
            ])
            | Enum.map(dav_resource.children, fn child ->
                response([
                  href(get_prefix(conn) <> child.href) | get_propstat(child, values: false)
                ])
              end)
          ]
      end

    tree = multistatus(responses)

    ExDav.DavView.render_tree(conn, tree)
  end

  defp handle_props(conn = %{assigns: %{depth: depth}}, props, dav_resource) do
    responses =
      cond do
        is_nil(dav_resource.children) or depth == 0 ->
          [
            response([
              href(get_prefix(conn) <> dav_resource.href)
              | get_propstat(dav_resource, props: props)
            ])
          ]

        true ->
          [
            response([
              href(get_prefix(conn) <> dav_resource.href)
              | get_propstat(dav_resource, props: props)
            ])
            | Enum.map(dav_resource.children, fn child ->
                response([
                  href(get_prefix(conn) <> child.href) | get_propstat(child, props: props)
                ])
              end)
          ]
      end

    tree = multistatus(responses)

    ExDav.DavView.render_tree(conn, tree)
  end

  def handle_propfind(conn = %{assigns: %{dav_path: path, dav_provider: {dav_provider, opts}}}) do
    resource = dav_provider.resolve(path, opts)

    case resource do
      nil ->
        send_resp(conn, 404, "Not found")

      _resource ->
        dav_resource = dav_provider.to_dav_struct(resource)
        {:ok, body, conn} = Plug.Conn.read_body(conn, [])

        # IO.inspect(body)

        if body == "" do
          handle_allprop(conn, dav_resource)
        else
          case Saxy.parse_string(body, ExDav.XMLHandler, %{}) do
            {:ok, %{propfind: %{allprop: true}}} ->
              handle_allprop(conn, dav_resource)

            {:ok, %{propfind: %{propname: true}}} ->
              handle_propname(conn, dav_resource)

            {:ok, %{propfind: %{prop: props}}} ->
              handle_props(conn, props, dav_resource)

            other ->
              IO.inspect(other)
              send_resp(conn, 400, "Invalid body")
          end
        end
    end
  end

  def handle_proppatch(conn) do
    send_resp(conn, 400, "")
  end

  defp content_length(conn) do
    with [value] <- get_req_header(conn, "content-length"),
         {number, _rest} <- Integer.parse(value) do
      number
    else
      [] -> 0
      :error -> 0
    end
  end

  defp get_parent(%{path_info: []}), do: nil

  defp get_parent(conn) do
    {_, parent_paths} = List.pop_at(conn.path_info, -1)

    paths =
      parent_paths
      |> Enum.join("/")
      |> URI.decode()

    "/#{paths}"
  end

  def handle_mkcol(
        conn = %{assigns: %{dav_path: path, dav_name: name, dav_provider: {dav_provider, opts}}}
      ) do
    parent_path = get_parent(conn)

    cond do
      dav_provider.read_only() ->
        send_resp(conn, 403, "This server does not support write requests.")

      content_length(conn) != 0 ->
        send_resp(conn, 415, "This server does not process MKCOL requests with a request body.")

      dav_provider.exists(path, opts) ->
        send_resp(conn, 405, "You cannot MKCOL an existing resource.")

      not dav_provider.exists(parent_path, opts) or
          not dav_provider.is_collection(dav_provider.resolve(parent_path, opts)) ->
        send_resp(conn, 409, "The parent resource must be an existing collection.")

      true ->
        ref = dav_provider.resolve(parent_path, opts)

        with :ok <- dav_provider.create_collection(ref, name) do
          send_resp(conn, 201, "")
        else
          _ -> send_resp(conn, 403, "There was an error creating this collection.")
        end
    end
  end

  def handle_post(conn) do
    send_resp(conn, 400, "")
  end

  def handle_delete(
        conn = %{assigns: %{dav_path: path, dav_provider: {dav_provider, opts}, depth: depth}}
      ) do
    resource = dav_provider.resolve(path, opts)

    cond do
      dav_provider.read_only() ->
        send_resp(conn, 403, "This server does not support write requests.")

      content_length(conn) != 0 ->
        send_resp(conn, 415, "This server does not process DELETE requests with a request body.")

      is_nil(resource) ->
        send_resp(conn, 404, "Not found.")

      dav_provider.is_collection(resource) and depth != :infinity ->
        send_resp(conn, 400, "Only Depth: infinity is supported for collections.")

      dav_provider.supports_recursive_delete() ->
        with :ok <- dav_provider.delete(resource) do
          send_resp(conn, 204, "")
        else
          # TODO: provide the correct error list
          _other -> send_resp(conn, 400, "Delete request failed.")
        end

      true ->
        # TODO: get list of descendents and delete all of them
        send_resp(conn, 501, "Not implemented...")
    end
  end

  defp stream_body(conn, dav_provider, resource) do
    stream =
      Stream.resource(
        fn -> {conn, :reading} end,
        fn
          {conn, :reading} ->
            case Plug.Conn.read_body(conn, length: 8 * 1000) do
              {:ok, body, conn} -> {[body], {conn, :done}}
              {:more, chunk, conn} -> {[chunk], {conn, :reading}}
              {:error, reason} -> {:halt, {conn, reason}}
            end

          {conn, :done} ->
            {:halt, {conn, :done}}
        end,
        fn
          {conn, :done} ->
            send(self(), {:stream_body_done, conn})

          {conn, error_reason} ->
            send(self(), {:stream_body_error, {conn, error_reason}})

          other ->
            send(self(), {:stream_body_error, {conn, other}})
        end
      )

    dav_provider.write_stream(resource, stream)
    # we send the conn when uploading is done (or failed)
    receive do
      {:stream_body_done, conn} -> {:ok, conn}
      {:stream_body_error, result} -> {:error, result}
    after
      1_000 -> {:error, :timeout}
    end
  end

  defp read_to_void(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, _body, conn} ->
        {:ok, conn}

      {:more, _chunk, conn} ->
        read_to_void(conn)

      other ->
        {:error, {conn, other}}
    end
  end

  def handle_put(
        conn = %{assigns: %{dav_path: path, dav_name: name, dav_provider: {dav_provider, opts}}}
      ) do
    is_new = Map.get(conn.assigns, :is_new, false)
    resource = dav_provider.resolve(path, opts)
    parent_path = get_parent(conn)
    parent_resource = dav_provider.resolve(parent_path, opts)

    cond do
      get_req_header(conn, "content-range") != [] ->
        send_resp(conn, 400, "Content-range header is not allowed on PUT requests.")

      dav_provider.is_collection(resource) ->
        send_resp(conn, 405, "Cannot PUT to a collection.")

      not dav_provider.exists(parent_path, opts) or
          not dav_provider.is_collection(parent_resource) ->
        send_resp(conn, 409, "The parent resource must be an existing collection.")

      is_nil(resource) ->
        :ok = dav_provider.create_empty_resource(parent_resource, name)
        # recurse!
        conn
        |> assign(:is_new, true)
        |> handle_put()

      dav_provider.supports_streaming_uploads(resource) ->
        with {:ok, conn} <- read_to_void(conn) do
          send_resp(conn, if(is_new, do: 201, else: 204), "")
        else
          other ->
            IO.inspect(other)
            send_resp(conn, 500, "woopsie!")
        end

      # stream the request body
      # with {:ok, conn} <- stream_body(conn, dav_provider, resource) do
      #   send_resp(conn, if(is_new, do: 201, else: 204), "")
      # else
      #   {:error, {conn, reason}} when is_struct(conn) ->
      #     IO.inspect(reason, label: "upload error")
      #     send_resp(conn, 500, "upload error!")

      #   _other ->
      #     send_resp(conn, 500, "woopsie!")
      # end

      true ->
        # read whole body into memory :(
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        with :ok <- dav_provider.write(resource, body) do
          send_resp(conn, if(is_new, do: 201, else: 204), "")
        else
          _other -> send_resp(conn, 500, "woopsie!")
        end
    end
  end

  def handle_copy(conn) do
    send_resp(conn, 400, "")
  end

  def handle_move(conn) do
    send_resp(conn, 400, "")
  end

  def handle_lock(conn) do
    send_resp(conn, 501, "Locking is not implemented")
  end

  def handle_unlock(conn) do
    send_resp(conn, 501, "Locking is not implemented")
  end

  defp option_headers() do
    options = [
      {"Content-Type", "text/xml"},
      {"Content-Length", "0"},
      {"DAV", "1"}
    ]

    options =
      if Application.get_env(:ex_dav, :add_ms_author_via, true),
        do: [{"MS-Author-Via", "Dav"} | options],
        else: options

    options
  end

  def handle_options(conn = %Plug.Conn{path_info: ["/"]}),
    do: handle_options(%{conn | path_info: ["*"]})

  def handle_options(conn = %Plug.Conn{path_info: ["*"]}) do
    conn
    |> merge_resp_headers(option_headers())
    |> send_resp(200, "")
  end

  def handle_options(
        conn = %{
          assigns: %{
            dav_path: path,
            dav_provider: {dav_provider, opts},
            lock_manager: {lock_manager, _}
          }
        }
      ) do
    resource = dav_provider.resolve(path, opts)

    case resource do
      nil ->
        send_resp(conn, 404, "Not found")

      _resource ->
        allow =
          ["GET", "HEAD", "PROPFIND"]
          |> (&if(lock_manager, do: ["LOCK", "UNLOCK" | &1], else: &1)).()
          |> (&if(not dav_provider.read_only(),
                do: ["PUT", "DELETE", "COPY", "MOVE", "PROPPATCH" | &1],
                else: &1
              )).()

        conn
        |> put_resp_header("Content-Type", "text/xml")
        |> put_resp_header("Content-Length", "0")
        |> put_resp_header("DAV", "1")
        |> put_resp_header("Allow", Enum.join(allow, ", "))
        |> put_resp_header("MS-Author-Via", "DAV")
        |> send_resp(200, "")
    end
  end

  def handle_get(
        conn = %{assigns: %{dav_path: path, dav_provider: {dav_provider, opts}}},
        get_opts \\ []
      ) do
    resource = dav_provider.resolve(path, opts)
    is_head = Keyword.get(get_opts, :head, false)

    cond do
      is_nil(resource) ->
        send_resp(conn, 404, "Not found")

      dav_provider.is_collection(resource) ->
        send_resp(conn, 501, "Getting collections is not implemented!")

      true ->
        send_resource(conn, resource, head: is_head)
    end
  end

  def dispatch(conn = %Plug.Conn{}, _opts) do
    case conn.method do
      "PROPFIND" -> handle_propfind(conn)
      "PROPPATCH" -> handle_proppatch(conn)
      "MKCOL" -> handle_mkcol(conn)
      "POST" -> handle_post(conn)
      "DELETE" -> handle_delete(conn)
      "PUT" -> handle_put(conn)
      "COPY" -> handle_copy(conn)
      "MOVE" -> handle_move(conn)
      "LOCK" -> handle_lock(conn)
      "UNLOCK" -> handle_unlock(conn)
      "OPTIONS" -> handle_options(conn)
      "HEAD" -> handle_get(conn, head: true)
      "GET" -> handle_get(conn, [])
    end
  end
end
