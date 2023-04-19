defmodule DartSassTest do
  use ExUnit.Case, async: true

  @version DartSass.latest_version()

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
    Application.put_env(:dart_sass, :version, "1.58.0")

    Mix.Task.rerun("sass.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ "1.58.0"

    Application.delete_env(:dart_sass, :version)

    Mix.Task.rerun("sass.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ @version
  end

  test "errors on invalid profile" do
    assert_raise ArgumentError,
                 ~r<unknown dart_sass profile. Make sure the profile named :"assets/css/app.scss" is defined>,
                 fn ->
                   assert DartSass.run(:"assets/css/app.scss", ["../priv/static/assets/app.css"])
                 end
  end

  @tag platform: :linux
  test "errors on older Linux package version" do
    Application.put_env(:dart_sass, :version, "1.57.1")

    assert_raise RuntimeError, ~r/requires version >= 1.58.0, got: "1.57.1"/, fn ->
      Mix.Task.rerun("sass.install", ["--if-missing"])
    end

    Application.delete_env(:dart_sass, :version)
  end

  @tag :tmp_dir
  test "compiles", %{tmp_dir: dir} do
    dest = Path.join(dir, "app.css")
    Mix.Task.rerun("sass", ["default", "--no-source-map", "test/fixtures/app.scss", dest])
    assert File.read!(dest) == "body > p {\n  color: green;\n}\n"
  end
end
