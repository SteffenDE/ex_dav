defmodule ExDav.XMLHelpers do
  import Saxy.XML

  def href(link) do
    element("href", [], link)
  end

  defp get_props_from_resource(props, values) do
    Enum.map(props, fn {key, value} ->
      val = if(values, do: value, else: nil)
      element(key, [], val)
    end)
  end

  defp map_props_from_resource(props, requested_props) do
    Enum.reduce(
      requested_props,
      %{found: [], not_found: [], ns: %{}},
      fn %{name: name, ns: ns}, acc ->
        case ns do
          {key, "DAV:"} ->
            mapped_name = String.replace(name, "#{key}:", "")

            found? = Map.keys(props) |> Enum.map(&Atom.to_string/1) |> Enum.member?(mapped_name)

            key = if found?, do: :found, else: :not_found
            value = if found?, do: props[String.to_atom(mapped_name)], else: nil
            update_in(acc, [key], fn items -> [element(mapped_name, [], value) | items] end)

          {key, value} ->
            # we do not support other namespaces as "DAV:" currently
            acc
            |> update_in([:not_found], fn items -> [element(name, [], []) | items] end)
            |> update_in([:ns], fn nsmap -> Map.merge(nsmap, %{key => value}) end)
        end
      end
    )
  end

  def prop(%ExDav.DavResource{props: props}, opts \\ []) do
    values = Keyword.get(opts, :values, true)
    requested_props = Keyword.get(opts, :props, :all)

    props =
      if requested_props == :all do
        %{found: get_props_from_resource(props, values), ns: %{}}
      else
        map_props_from_resource(props, requested_props)
      end

    attrs =
      Enum.map(props.ns, fn {key, value} ->
        {"xmlns:#{key}", value}
      end)

    Enum.map(props, fn
      {:found, props} -> {element("prop", attrs, props), "HTTP/1.1 200 OK"}
      {:not_found, props} -> {element("prop", attrs, props), "HTTP/1.1 404 Not Found"}
      _ -> nil
    end)
    |> Enum.filter(fn
      {_, []} -> false
      item -> not is_nil(item)
    end)
  end

  def propstat(props, status \\ "HTTP/1.1 200 OK") do
    element("propstat", [], [element("status", [], status) | [props]])
  end

  def response(elements, attrs \\ []) do
    element("response", attrs, elements)
  end

  def multistatus(responses, attrs \\ [{"xmlns", "DAV:"}]) do
    element("multistatus", attrs, responses)
  end
end
