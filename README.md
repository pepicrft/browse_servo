# BrowseServo

BrowseServo is a Rustler-backed Elixir browser runtime for Elixir applications that want
an idiomatic browser API with a native process boundary and a Servo-backed execution
engine.

It follows the same shared-interface pattern used by `Chrona`: BrowseServo implements
the shared [`Browse`](https://hex.pm/packages/browse) browser contract over a Servo-backed
native runtime.

The architectural boundary is:

- an Elixir `GenServer` owns the browser runtime
- Rustler NIF resources hold the native runtime state
- Elixir modules expose the `Browse.Browser` contract over direct native method calls

## 📦 Installation

```elixir
def deps do
  [
    {:browse_servo, "~> 0.1.0-dev"}
  ]
end
```

For development in this repository:

```bash
mise install
mix setup
```

## 🧭 Usage

### Start a browser runtime directly

```elixir
{:ok, browser} = BrowseServo.start_link()
```

### Use the browser contract directly

```elixir
:ok = BrowseServo.Browser.navigate(browser, "https://example.com/docs")
{:ok, url} = BrowseServo.Browser.current_url(browser)
{:ok, html} = BrowseServo.Browser.content(browser)
{:ok, value} = BrowseServo.Browser.evaluate(browser, "document.title")
{:ok, image} = BrowseServo.Browser.capture_screenshot(browser, format: "png")
```

### Use Browse-backed pools

Configure pools through BrowseServo:

```elixir
config :browse_servo,
  default_pool: MyApp.BrowseServoPool,
  pools: [
    MyApp.BrowseServoPool: [pool_size: 2]
  ]
```

Add the configured pools to your supervision tree:

```elixir
children = BrowseServo.children()
```

Or start one pool directly:

```elixir
children = [
  {BrowseServo.BrowserPool, name: MyApp.BrowseServoPool, pool_size: 2}
]
```

Check out a warm browser from the pool:

```elixir
BrowseServo.checkout(fn browser ->
  :ok = BrowseServo.Browser.navigate(browser, "https://example.com")
  BrowseServo.Browser.capture_screenshot(browser, format: "png")
end)
```

## 🧩 Native Layer

`BrowseServo.Native` uses `RustlerPrecompiled`, so published releases ship precompiled
NIFs and downstream users do not need Rust or Cargo installed.

During local development the `0.1.0-dev` version force-builds the NIF from source.

The native crate links directly against Servo from the upstream Servo repository, pinned
to a specific commit in `native/browse_servo_native/Cargo.toml`.

For repository development, `mise.toml` also pins Python 3.12 because current Servo
code generation requires Python 3.11+.

## 📡 Telemetry

BrowseServo emits telemetry events aligned with `browse_chrome`:

- `[:browse, :checkout, :start | :stop | :exception]`
- `[:browse_servo, :browser, :init, :start | :stop | :exception]`
- `[:browse_servo, :browser, :capture, :start | :stop | :exception]`

BrowseServo also emits operation-specific browser events under the `[:browse_servo, :browser, ...]` prefix for:

- runtime initialization
- navigation
- content reads and evaluation
- screenshot capture
- PDF export
- element interaction and waits

Operation-level events are emitted as spans, so consumers get `:start`, `:stop`, and
`:exception` events with timing metadata.

## 🚢 Releasing

The repository includes:

- `git-cliff` configuration in `cliff.toml`
- CI checks for tests, warning-free compilation, and formatting
- a `Release` workflow that builds precompiled NIFs for Linux, macOS, and Windows
- checksum generation for `RustlerPrecompiled`
- atomic git push of the release commit and tag with `git push --atomic`

The release workflow is triggered manually from GitHub Actions and accepts a semver
version like `0.1.0`.

The git ref update is atomic for the release commit and tag. GitHub release creation runs
immediately after that successful push.

## 📄 License

MIT
