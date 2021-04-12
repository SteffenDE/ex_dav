defmodule ExDav.HTTPChunker do
  @callback chunk_to_conn(Plug.Conn.t(), any()) :: {:ok, Plug.Conn.t()} | {:error, any()}
  def chunk_to_conn(conn, current_chunk) do
    Plug.Conn.chunk(conn, current_chunk)
  end
end

defmodule ExDav.HTTPServer do
  use Plug.Router

  require Logger

  import ExDav.XMLHelpers

  @chunker Application.compile_env(:ex_dav, [:http_server, :chunker], ExDav.HTTPChunker)

  plug(Plug.Logger)
  plug(:check_readonly)
  plug(:assign_depth)
  plug(:disallow_infinity)
  plug(ExDav.AuthPlug)
  plug(:match)
  plug(:dispatch)

  def dav_provider() do
    Application.get_env(:ex_dav, :dav_provider, ExDav.FileSystemProvider)
  end

  def lock_manager() do
    Application.get_env(:ex_dav, :lock_manager)
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

  defp check_readonly(conn, _opts) do
    send_forbidden_if_write(conn, dav_provider().read_only())
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

  # sending files

  defp maybe_set_range_response(conn, resource, true) do
    content_length = ExDav.Resource.get_content_length(resource)

    {conn, 200, content_length, 0, content_length - 1}
  end

  defp maybe_set_range_response(conn, resource, false) do
    is_range_request = not Enum.empty?(get_req_header(conn, "range"))
    file_length = ExDav.Resource.get_content_length(resource)

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

  defp send_resource(conn, resource, opts \\ []) do
    head = Keyword.get(opts, :head, false)
    is_range_request = not Enum.empty?(get_req_header(conn, "range"))
    supports_ranges = dav_provider().supports_ranges()
    supports_streaming = dav_provider().supports_streaming()
    supports_content_length = dav_provider().supports_content_length()
    content_length = ExDav.Resource.get_content_length(resource)
    content_type = ExDav.Resource.get_content_type(resource)
    display_name = ExDav.Resource.get_display_name(resource)

    ignore_ranges =
      not is_range_request or not supports_ranges or not supports_content_length or
        content_length == 0

    {conn, code, content_length, range_start, range_end} =
      maybe_set_range_response(conn, resource, ignore_ranges)

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
          ExDav.Resource.get_stream(resource, range: {range_start, range_end})
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
              ExDav.Resource.get_content(resource, range: {range_start, range_end})
            )

          conn
        end
    end
  end

  # request handlers

  defp get_propstat(%ExDav.DavResource{} = resource, opts \\ []) do
    prop(resource, opts)
    |> Enum.map(fn {props, status} -> propstat(props, status) end)
  end

  defp handle_allprop(conn = %{assigns: %{depth: depth}}, dav_resource) do
    responses =
      cond do
        is_nil(dav_resource.children) or depth == 0 ->
          [response([href(dav_resource.href) | get_propstat(dav_resource)])]

        true ->
          [
            response([href(dav_resource.href) | get_propstat(dav_resource)])
            | Enum.map(dav_resource.children, fn child ->
                response([href(child.href) | get_propstat(child)])
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
          [response([href(dav_resource.href) | get_propstat(dav_resource, values: false)])]

        true ->
          [
            response([href(dav_resource.href) | get_propstat(dav_resource, values: false)])
            | Enum.map(dav_resource.children, fn child ->
                response([href(child.href) | get_propstat(child, values: false)])
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
          [response([href(dav_resource.href) | get_propstat(dav_resource, props: props)])]

        true ->
          [
            response([href(dav_resource.href) | get_propstat(dav_resource, props: props)])
            | Enum.map(dav_resource.children, fn child ->
                response([href(child.href) | get_propstat(child, props: props)])
              end)
          ]
      end

    tree = multistatus(responses)

    ExDav.DavView.render_tree(conn, tree)
  end

  def handle_propfind(conn) do
    resource = dav_provider().resolve(conn)

    case resource do
      nil ->
        send_resp(conn, 404, "Not found")

      _resource ->
        dav_resource = ExDav.Resource.to_dav_struct(resource)
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

  def handle_mkcol(conn) do
    send_resp(conn, 400, "")
  end

  def handle_post(conn) do
    send_resp(conn, 400, "")
  end

  def handle_delete(conn) do
    send_resp(conn, 400, "")
  end

  def handle_put(conn) do
    send_resp(conn, 400, "")
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

  def handle_options(conn) do
    resource = dav_provider().resolve(conn)

    case resource do
      nil ->
        send_resp(conn, 404, "Not found")

      _resource ->
        allow =
          ["GET", "HEAD", "PROPFIND"]
          |> (&if(lock_manager(), do: ["LOCK", "UNLOCK" | &1], else: &1)).()
          |> (&if(not dav_provider().read_only(),
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

  def handle_get(conn) do
    resource = dav_provider().resolve(conn)

    case resource do
      nil -> send_resp(conn, 404, "Not found")
      resource -> send_resource(conn, resource)
    end
  end

  def handle_head(conn) do
    resource = dav_provider().resolve(conn)

    case resource do
      nil -> send_resp(conn, 404, "Not found")
      resource -> send_resource(conn, resource, head: true)
    end
  end

  # router matches

  match _, via: :propfind do
    handle_propfind(conn)
  end

  match _, via: :proppatch do
    handle_proppatch(conn)
  end

  match _, via: :mkcol do
    handle_mkcol(conn)
  end

  match _, via: :post do
    handle_post(conn)
  end

  match _, via: :delete do
    handle_delete(conn)
  end

  match _, via: :put do
    handle_put(conn)
  end

  match _, via: :copy do
    handle_copy(conn)
  end

  match _, via: :move do
    handle_move(conn)
  end

  match _, via: :lock do
    handle_lock(conn)
  end

  match _, via: :unlock do
    handle_unlock(conn)
  end

  match _, via: :options do
    handle_options(conn)
  end

  match _, via: :get do
    handle_get(conn)
  end

  match _, via: :head do
    handle_head(conn)
  end
end
