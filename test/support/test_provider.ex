defmodule ExDav.TestFile do
  defstruct name: "myfile",
            path: "/my/existing/file",
            contentlength: 3,
            contenttype: "text/plain"
end

defmodule ExDav.TestProvider do
  use ExDav.DavProvider

  @impl true
  def read_only(), do: true

  @impl true
  def resolve(path, _opts) do
    case path do
      "/my/existing/file" -> %ExDav.TestFile{}
      _ -> nil
    end
  end

  @impl true
  def get_creation_date(_ref), do: NaiveDateTime.utc_now()

  @impl true
  def get_last_modified(_ref), do: NaiveDateTime.utc_now()

  @impl true
  def get_members(_ref), do: []

  @impl true
  def get_preferred_path(ref), do: ref.path

  @impl true
  def is_collection(_ref), do: false

  @impl true
  def get_content_length(ref), do: ref.contentlength

  @impl true
  def get_content_type(ref), do: ref.contenttype

  @impl true
  def get_display_name(ref), do: ref.name

  @impl true
  def get_content(ref, _opts), do: String.duplicate("A", ref.contentlength)

  @impl true
  def get_stream(_ref, _opts), do: raise("not implemented")
end
