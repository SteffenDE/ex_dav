defmodule ExDavDemoTest do
  use ExUnit.Case
  doctest ExDavDemo

  test "greets the world" do
    assert ExDavDemo.hello() == :world
  end
end
