defmodule DartSassTest do
  use ExUnit.Case, async: true

  @version "1.38.1"

  test "run on default" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ @version
  end

  test "run on profile" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:another, []) == 0
           end) =~ @version
  end

  test "updates on install" do
    Application.put_env(:dart_sass, :version, "1.36.0")

    Mix.Task.rerun("sass.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ "1.36.0"

    Application.delete_env(:dart_sass, :version)

    Mix.Task.rerun("sass.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ @version
  end
end
