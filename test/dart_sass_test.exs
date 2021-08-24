defmodule DartSassTest do
  use ExUnit.Case, async: true

  test "run on default" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ "1.38.1"
  end

  test "run on profile" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:another, []) == 0
           end) =~ "1.38.1"
  end
end
