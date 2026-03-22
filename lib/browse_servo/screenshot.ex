defmodule BrowseServo.Screenshot do
  @moduledoc false

  @default_width 1280
  @default_height 720

  @spec capture(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def capture(url, opts \\ []) when is_binary(url) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    chrome_path = chrome_path(opts)
    output = temp_file_path()

    args = [
      "--headless",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--hide-scrollbars",
      "--screenshot=#{output}",
      "--window-size=#{width},#{height}",
      url
    ]

    try do
      with {:ok, chrome_path} <- chrome_path,
           {_command_output, 0} <- System.cmd(chrome_path, args, stderr_to_stdout: true),
           {:ok, image} <- File.read(output) do
        {:ok, image}
      else
        {:error, _} = error ->
          error

        {command_output, status} ->
          {:error, {:chrome_exit, status, command_output}}
      end
    after
      File.rm(output)
    end
  end

  defp chrome_path(opts) do
    opts
    |> Keyword.get(
      :chrome_path,
      Application.get_env(:browse_servo, :chrome_path) || System.get_env("CHROME_PATH")
    )
    |> case do
      nil -> detect_chrome_path()
      path -> {:ok, path}
    end
  end

  defp detect_chrome_path do
    [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "google-chrome-stable",
      "google-chrome",
      "chromium",
      "chromium-browser",
      "chrome",
      "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
      "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"
    ]
    |> Enum.find(&chrome_exists?/1)
    |> case do
      nil -> {:error, :chrome_not_found}
      path -> {:ok, path}
    end
  end

  defp chrome_exists?(path) do
    (String.contains?(path, "/") or String.contains?(path, "\\"))
    |> case do
      true -> File.exists?(path)
      false -> System.find_executable(path) != nil
    end
  end

  defp temp_file_path do
    Path.join(
      System.tmp_dir!(),
      "browse_servo-screenshot-#{System.unique_integer([:positive])}.png"
    )
  end
end
