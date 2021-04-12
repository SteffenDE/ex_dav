defmodule ExDav.XMLHandler do
  @behaviour Saxy.Handler

  defp add_namespaces(state, attributes) do
    namespaces =
      attributes
      |> Enum.map(fn {key, value} ->
        # IO.inspect(key)

        case key do
          "xmlns:" <> namespace ->
            {namespace, value}

          "xmlns" ->
            {:default, value}

          _other ->
            nil
        end
      end)
      |> Enum.filter(fn val -> not is_nil(val) end)
      |> Enum.into(%{})

    case state do
      %{ns: ns} -> Map.put(state, :ns, Map.merge(ns, namespaces))
      _ -> Map.put(state, :ns, namespaces)
    end
  end

  defp get_dav_prefix(%{ns: ns}) do
    case Enum.find_value(ns, fn
           {key, "DAV:"} -> key
           _ -> nil
         end) do
      nil -> ""
      :default -> ""
      prefix -> "#{prefix}:"
    end
  end

  defp get_prop(%{ns: ns}, prop) do
    case Enum.find(ns, fn {key, _value} ->
           String.starts_with?(prop, "#{key}:")
         end) do
      nil -> %{name: prop, ns: {:default, "DAV:"}}
      namespace -> %{name: prop, ns: namespace}
    end
  end

  def handle_event(:start_document, _prolog, state) do
    {:ok, state}
  end

  # handle when inside propfind
  def handle_event(:start_element, {name, attributes}, state = %{propfind: %{}}) do
    state = add_namespaces(state, attributes)
    dav_prefix = get_dav_prefix(state)

    state =
      cond do
        name == "#{dav_prefix}allprop" ->
          put_in(state, [:propfind, :allprop], true)

        name == "#{dav_prefix}propname" ->
          put_in(state, [:propfind, :propname], true)

        name == "#{dav_prefix}prop" ->
          put_in(state, [:propfind, :prop], [])

        true ->
          update_in(state, [:propfind, :prop], fn props -> [get_prop(state, name) | props] end)
      end

    {:ok, state}
  end

  def handle_event(:start_element, {name, attributes}, state) do
    state = add_namespaces(state, attributes)
    dav_prefix = get_dav_prefix(state)

    # IO.inspect(name)
    # IO.inspect(dav_prefix)

    state =
      cond do
        name == "#{dav_prefix}propfind" -> Map.put(state, :propfind, %{})
        true -> state
      end

    {:ok, Map.put(state, :current_tag, name)}
  end

  def handle_event(:characters, _content, state) do
    # IO.inspect(content, label: "content (tag: #{current_tag})")
    {:ok, state}
  end

  def handle_event(:end_element, _, state) do
    {:ok, state}
  end

  def handle_event(:end_document, _data, state) do
    {:ok, state}
  end
end
