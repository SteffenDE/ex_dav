defmodule ExDav.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test

  import Mox

  @opts [dav_provider: ExDav.TestProvider]

  setup do
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
      response = sent_resp(ExDav.Plug.call(conn, @opts))

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
      ExDav.Plug.call(conn, @opts)

      assert_received {:chunked_msg, "AAA"}
    end
  end

  describe "propfind" do
    test "finite depth error when no depth header is set (no header -> infinite)" do
      conn = conn(:propfind, "/my/existing/file")
      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {403, _,
              ~s(<?xml version="1.0" encoding="utf-8" ?><error xmlns="DAV:"><propfind-finite-depth/></error>)} =
               response
    end

    test "404" do
      conn =
        conn(:propfind, "/my/not/existing/file")
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {404, _, _} = response
    end

    test "allprop (no request body)" do
      conn =
        conn(:propfind, "/my/existing/file")
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {200, _, body} = response

      assert {:ok, {"multistatus", [{"xmlns", "DAV:"}], responses}} =
               Saxy.SimpleForm.parse_string(body)

      assert [
               {"response", [],
                [
                  {"href", [], ["/my/existing/file"]},
                  {"propstat", [],
                   [
                     {"status", [], ["HTTP/1.1 200 OK"]},
                     {"prop", [], props}
                   ]}
                ]}
             ] = responses

      assert Enum.find(props, fn
               {"creationdate", [], [_]} -> true
               _ -> false
             end)

      assert Enum.find(props, fn
               {"getlastmodified", [], [_]} -> true
               _ -> false
             end)

      assert {"displayname", [], ["myfile"]} in props
      assert {"getcontentlength", [], ["3"]} in props
      assert {"getcontenttype", [], ["text/plain"]} in props
    end

    test "allprop" do
      conn =
        conn(:propfind, "/my/existing/file", ~s(\
<?xml version="1.0" encoding="utf-8" ?>
  <D:propfind xmlns:D="DAV:">
    <D:allprop/>
</D:propfind>))
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {200, _, body} = response

      assert {:ok, {"multistatus", [{"xmlns", "DAV:"}], responses}} =
               Saxy.SimpleForm.parse_string(body)

      assert [
               {"response", [],
                [
                  {"href", [], ["/my/existing/file"]},
                  {"propstat", [],
                   [
                     {"status", [], ["HTTP/1.1 200 OK"]},
                     {"prop", [], props}
                   ]}
                ]}
             ] = responses

      assert Enum.find(props, fn
               {"creationdate", [], [_]} -> true
               _ -> false
             end)

      assert Enum.find(props, fn
               {"getlastmodified", [], [_]} -> true
               _ -> false
             end)

      assert {"displayname", [], ["myfile"]} in props
      assert {"getcontentlength", [], ["3"]} in props
      assert {"getcontenttype", [], ["text/plain"]} in props
    end

    test "propname" do
      conn =
        conn(:propfind, "/my/existing/file", ~s(\
<?xml version="1.0" encoding="utf-8" ?>
  <D:propfind xmlns:D="DAV:">
    <D:propname/>
</D:propfind>))
        |> Plug.Conn.put_req_header("depth", "1")

      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {200, _, body} = response

      assert {:ok, {"multistatus", [{"xmlns", "DAV:"}], responses}} =
               Saxy.SimpleForm.parse_string(body)

      assert [
               {"response", [],
                [
                  {"href", [], ["/my/existing/file"]},
                  {"propstat", [],
                   [
                     {"status", [], ["HTTP/1.1 200 OK"]},
                     {"prop", [], props}
                   ]}
                ]}
             ] = responses

      assert {"creationdate", [], []} in props
      assert {"getlastmodified", [], []} in props
      assert {"displayname", [], []} in props
      assert {"getcontentlength", [], []} in props
      assert {"getcontenttype", [], []} in props
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

      response = sent_resp(ExDav.Plug.call(conn, @opts))

      assert {200, _, body} = response

      assert {:ok, {"multistatus", [{"xmlns", "DAV:"}], responses}} =
               Saxy.SimpleForm.parse_string(body)

      assert [
               {"response", [],
                [
                  {"href", [], ["/my/existing/file"]},
                  {"propstat", [],
                   [
                     {"status", [], ["HTTP/1.1 200 OK"]},
                     {"prop", [{"xmlns:R", "http://ns.example.com/boxschema/"}], found_props}
                   ]},
                  {"propstat", [],
                   [
                     {"status", [], ["HTTP/1.1 404 Not Found"]},
                     {"prop", [{"xmlns:R", "http://ns.example.com/boxschema/"}], not_found_props}
                   ]}
                ]}
             ] = responses

      assert {"getcontentlength", [], ["3"]} in found_props

      assert {"R:bigbox", [], []} in not_found_props
      assert {"R:author", [], []} in not_found_props
      assert {"R:DingALing", [], []} in not_found_props
      assert {"R:Random", [], []} in not_found_props
    end
  end
end
