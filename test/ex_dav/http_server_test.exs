defmodule ExDav.HTTPServerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Mox

  setup do
    Application.put_env(:ex_dav, :dav_provider, ExDav.TestProvider)
    Application.put_env(:ex_dav, :domain_controller, ExDav.AnonymousDC)

    ExDav.HTTPChunkerMock
    |> stub(:chunk_to_conn, fn conn, chunk ->
      send(self(), {:chunked_msg, chunk})
      Plug.Conn.chunk(conn, chunk)
    end)

    %{}
  end

  defp assert_header(headers, key, value) do
    assert Enum.find(headers, fn
             {^key, ^value} -> true
             _ -> false
           end)
  end

  describe "options" do
    test "returns the valid headers" do
      conn = conn(:options, "/my/existing/file")
      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {200, headers, ""} = response

      assert_header(headers, "DAV", "1")
      assert_header(headers, "Content-Length", "0")
      assert_header(headers, "Content-Type", "text/xml")
      assert_header(headers, "Allow", "GET, HEAD, PROPFIND")
    end
  end

  describe "get" do
    test "returns content" do
      conn = conn(:get, "/my/existing/file")
      ExDav.HTTPServer.call(conn, [])

      assert_received {:chunked_msg, "AAA"}
    end
  end

  describe "propfind" do
    test "finite depth error when no depth header is set (no header -> infinite)" do
      conn = conn(:propfind, "/my/existing/resource")
      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {403, _,
              ~s(<?xml version="1.0" encoding="utf-8" ?><error xmlns="DAV:"><propfind-finite-depth/></error>)} =
               response
    end

    test "404" do
      conn =
        conn(:propfind, "/my/not/existing/file")
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {404, _, _} = response
    end

    test "allprop (no request body)" do
      conn =
        conn(:propfind, "/my/existing/file")
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {200, _, body} = response

      assert body ==
               ~s(\
<?xml version="1.0" encoding="utf-8" ?>
<multistatus xmlns="DAV:">
  <response>
    <href>/my/existing/file</href>
    <propstat>
      <status>HTTP/1.1 200 OK</status>
      <prop>
        <displayname>myfile</displayname>
        <getcontentlength>3</getcontentlength>
        <getcontenttype>text/plain</getcontenttype>
      </prop>
    </propstat>
  </response>
</multistatus>)
               |> String.replace(~r/[\n\r]\s+/, "")
               |> String.replace(~r/[\n\r]+/, "")
    end

    test "allprop" do
      conn =
        conn(:propfind, "/my/existing/file", ~s(\
<?xml version="1.0" encoding="utf-8" ?>
  <D:propfind xmlns:D="DAV:">
    <D:allprop/>
</D:propfind>))
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {200, _, body} = response

      assert body ==
               ~s(\
<?xml version="1.0" encoding="utf-8" ?>
<multistatus xmlns="DAV:">
  <response>
    <href>/my/existing/file</href>
    <propstat>
      <status>HTTP/1.1 200 OK</status>
      <prop>
        <displayname>myfile</displayname>
        <getcontentlength>3</getcontentlength>
        <getcontenttype>text/plain</getcontenttype>
      </prop>
    </propstat>
  </response>
</multistatus>)
               |> String.replace(~r/[\n\r]\s+/, "")
               |> String.replace(~r/[\n\r]+/, "")
    end

    test "propname" do
      conn =
        conn(:propfind, "/my/existing/file", ~s(\
<?xml version="1.0" encoding="utf-8" ?>
  <D:propfind xmlns:D="DAV:">
    <D:propname/>
</D:propfind>))
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {200, _, body} = response

      assert body ==
               ~s(\
<?xml version="1.0" encoding="utf-8" ?>
<multistatus xmlns="DAV:">
  <response>
    <href>/my/existing/file</href>
    <propstat>
      <status>HTTP/1.1 200 OK</status>
      <prop>
        <displayname></displayname>
        <getcontentlength></getcontentlength>
        <getcontenttype></getcontenttype>
      </prop>
    </propstat>
  </response>
</multistatus>)
               |> String.replace(~r/[\n\r]\s+/, "")
               |> String.replace(~r/[\n\r]+/, "")
    end

    test "normal prop request" do
      conn =
        conn(:propfind, "/my/existing/file", ~s(\
<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop xmlns:R="http://ns.example.com/boxschema/">
    <R:bigbox/>
    <R:author/>
    <R:DingALing/>
    <R:Random/>
    <D:getcontentlength/>
  </D:prop>
</D:propfind>))
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.HTTPServer.call(conn, []))

      assert {200, _, body} = response

      assert body ==
               ~s(\
<?xml version="1.0" encoding="utf-8" ?>
<multistatus xmlns="DAV:">
  <response>
    <href>/my/existing/file</href>
    <propstat>
      <status>HTTP/1.1 200 OK</status>
      <prop xmlns:R="http://ns.example.com/boxschema/">
        <getcontentlength>3</getcontentlength>
      </prop>
    </propstat>
    <propstat>
      <status>HTTP/1.1 404 Not Found</status>
      <prop xmlns:R="http://ns.example.com/boxschema/">
        <R:bigbox/>
        <R:author/>
        <R:DingALing/>
        <R:Random/>
      </prop>
    </propstat>
  </response>
</multistatus>)
               |> String.replace(~r/[\n\r]\s+/, "")
               |> String.replace(~r/[\n\r]+/, "")
    end
  end
end
