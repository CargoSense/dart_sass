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
    Application.put_env(:dart_sass, :version, "1.74.1")

    Mix.Task.rerun("sass.install", ["--if-missing"])

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert DartSass.run(:default, ["--version"]) == 0
           end) =~ "1.74.1"

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

  test "errors on older package version" do
    Application.put_env(:dart_sass, :version, "1.72.0")

    assert_raise RuntimeError, ~r/requires version >= 1.74.1, got: "1.72.0"/, fn ->
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

  test "install_and_run/2 may be invoked concurrently" do
    bin_paths = DartSass.bin_paths()

    for path <- bin_paths, do: path |> File.stat()

    for path <- bin_paths do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> flunk("Could not delete #{inspect(path)}, reason: #{inspect(reason)}")
      end
    end

    results =
      [:extra1, :extra2, :extra3]
      |> Enum.map(fn profile ->
        Application.put_env(:dart_sass, profile, args: ["--version"])

        Task.async(fn ->
          ExUnit.CaptureIO.capture_io(fn ->
            return_code = DartSass.install_and_run(profile, [])

            # Let the first finished task set the binary files to read and execute only,
            # so that the others will fail if they try to overwrite them.
            for path <- bin_paths do
              File.chmod(path, 0o500)
            end

            assert return_code == 0
          end)
        end)
      end)
      |> Task.await_many(:infinity)

    # for path <- bin_paths do
    #   path |> File.stat() |> dbg()
    # end

    for path <- bin_paths do
      File.chmod!(path, 0o700)
    end

    assert Enum.all?(results)
  end
end
