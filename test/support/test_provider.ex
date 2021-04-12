defmodule ExDav.TestFile do
  defstruct name: "myfile",
            path: "/my/existing/file",
            contentlength: 3,
            contenttype: "text/plain"
end

defimpl ExDav.Resource, for: ExDav.TestFile do
  def to_dav_struct(ref),
    do: %ExDav.DavResource{
      href: ref.path,
      props: %{
        displayname: ref.name,
        getcontentlength: ref.contentlength,
        getcontenttype: ref.contenttype
      },
      children: []
    }

  def get_content_length(ref), do: ref.contentlength

  def get_content_type(ref), do: ref.contenttype

  def get_display_name(ref), do: ref.name

  def get_content(ref, _opts), do: String.duplicate("A", ref.contentlength)

  def get_stream(_ref, _opts), do: raise("not implemented")
end

defmodule ExDav.TestProvider do
  use ExDav.DavProvider

  @impl true
  def read_only(), do: true

  @impl true
  def resolve(conn) do
    case conn.path_info do
      ["my", "existing", "file"] -> %ExDav.TestFile{}
      _ -> nil
    end
  end

  def supports_ranges(), do: false
  def supports_streaming(), do: false
  def supports_content_length(), do: false
end
