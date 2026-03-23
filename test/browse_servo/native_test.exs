defmodule BrowseServo.NativeTest do
  use ExUnit.Case, async: true

  @moduletag skip:
               if(System.get_env("CI") == "true" and match?({:unix, :linux}, :os.type()),
                 do: "Servo NIF cannot be loaded on GitHub Linux runners due static TLS limits",
                 else: false
               )

  test "native runtime returns capabilities" do
    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, capabilities} = BrowseServo.Native.capabilities(runtime)
    assert capabilities.engine == :browse_servo
    assert capabilities.embedding == :rustler
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end

  test "native runtime manages page state" do
    url =
      "data:text/html,%3C!doctype%20html%3E%3Ctitle%3EHello%3C%2Ftitle%3E%3Cbody%3E%3Cmain%20data-testid%3D%22greeting%22%3EHello%3C%2Fmain%3E%3C%2Fbody%3E"

    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, page} = BrowseServo.Native.open_page(runtime, url)
    assert {:ok, "Hello"} = BrowseServo.Native.title(runtime, page.id)

    assert {:ok, content} = BrowseServo.Native.content(runtime, page.id)
    assert content =~ "<title>Hello</title>"
    assert content =~ ~s(data-testid="greeting")

    assert {:ok, "Hello"} = BrowseServo.Native.evaluate(runtime, page.id, "document.title")

    assert :ok = BrowseServo.Native.close_page(runtime, page.id)
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end

  test "native runtime supports interaction, screenshots, and pdf output" do
    html = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Servo Actions</title>
      </head>
      <body>
        <input id="name" value="" />
        <button id="go" onclick="document.body.setAttribute('data-clicked', 'yes'); document.getElementById('ready').textContent = document.getElementById('name').value">Go</button>
        <div id="ready"></div>
      </body>
    </html>
    """

    url = "data:text/html;base64," <> Base.encode64(html)

    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, page} = BrowseServo.Native.open_page(runtime, url)

    assert :ok = BrowseServo.Native.fill(runtime, page.id, "#name", "hello servo")

    assert {:ok, "hello servo"} =
             BrowseServo.Native.evaluate(runtime, page.id, "document.querySelector('#name').value")

    assert :ok = BrowseServo.Native.click(runtime, page.id, "#go")
    assert :ok = BrowseServo.Native.wait_for(runtime, page.id, "#ready", 1_000)

    assert {:ok, "yes"} =
             BrowseServo.Native.evaluate(
               runtime,
               page.id,
               "document.body.getAttribute('data-clicked')"
             )

    assert {:ok, "hello servo"} =
             BrowseServo.Native.evaluate(
               runtime,
               page.id,
               "document.querySelector('#ready').textContent"
             )

    assert {:ok, <<137, 80, 78, 71, _::binary>>} =
             BrowseServo.Native.capture_screenshot(runtime, page.id, "png", 90)

    assert {:ok, <<37, 80, 68, 70, _::binary>>} = BrowseServo.Native.print_to_pdf(runtime, page.id)

    assert :ok = BrowseServo.Native.close_page(runtime, page.id)
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end

  test "native runtime navigates an existing page to a data url" do
    html = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Navigated</title>
      </head>
      <body>
        <main id="greeting">hello after navigate</main>
      </body>
    </html>
    """

    url = "data:text/html;base64," <> Base.encode64(html)

    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, page} = BrowseServo.Native.open_page(runtime, "about:blank")
    assert {:ok, page} = BrowseServo.Native.navigate(runtime, page.id, url)
    assert {:ok, "Navigated"} = BrowseServo.Native.title(runtime, page.id)

    assert {:ok, content} = BrowseServo.Native.content(runtime, page.id)
    assert content =~ "<title>Navigated</title>"
    assert content =~ ~s(<main id="greeting">hello after navigate</main>)

    assert {:ok, true} =
             BrowseServo.Native.evaluate(
               runtime,
               page.id,
               "document.querySelector('#greeting') !== null"
             )

    assert {:ok, <<137, 80, 78, 71, _::binary>>} =
             BrowseServo.Native.capture_screenshot(runtime, page.id, "png", 90)

    assert :ok = BrowseServo.Native.close_page(runtime, page.id)
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end
end
