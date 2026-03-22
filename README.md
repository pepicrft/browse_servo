# BrowseServo

BrowseServo is a Rustler-backed Elixir browser runtime for Elixir applications that want
an idiomatic browser API with a native process boundary.

It follows the same shared-interface pattern used by `Chrona`: BrowseServo keeps its own
API and native runtime, while delegating pool management and browser capability
integration to [`Browse`](https://hex.pm/packages/browse) under the hood.

The architectural boundary is:

- an Elixir `GenServer` owns the browser runtime
- Rustler NIF resources hold the native runtime state
- Elixir page/browser modules expose an idiomatic API over direct native method calls

## 🚀 Status

BrowseServo is a working project with a production-ready release pipeline, tested Elixir
API surface, telemetry instrumentation, and precompiled NIF distribution.

What is included today:

- package/app identity as `browse_servo`
- Rustler-based native crate under `native/browse_servo_native`
- `BrowseServo.Browser` as the Elixir process boundary
- `BrowseServo.BrowseBackend` and `BrowseServo.BrowserPool` as the Browse-backed integration layer
- `BrowseServo.Page` as the high-level page handle
- telemetry events for browser lifecycle and page operations
- precompiled-NIF publishing setup via `rustler_precompiled`
- tests, docs, formatting, and CI scaffolding

Current implementation notes:

- the native layer currently uses an in-memory browser model while the Servo embedding evolves
- the public Elixir API is stable and designed to carry forward to the Servo-backed runtime
- screenshot capture is currently rendered through headless Chrome while the Servo embedding evolves

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

### Open and use a page

```elixir
{:ok, page} = BrowseServo.Browser.new_page(browser, url: "https://example.com")
{:ok, page} = BrowseServo.Page.goto(page, "https://example.com/docs")
{:ok, title} = BrowseServo.Page.title(page)
{:ok, html} = BrowseServo.Page.content(page)
{:ok, value} = BrowseServo.Page.evaluate(page, "document.title")
```

### Inspect runtime capabilities

```elixir
{:ok, caps} = BrowseServo.Browser.capabilities(browser)
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

`BrowseServo.Native` uses `RustlerPrecompiled`, so published releases can ship precompiled NIFs and
downstream users do not need Rust installed.

During local development the `0.1.0-dev` version force-builds the NIF from source.

Screenshot capture currently uses a local Chrome/Chromium installation. BrowseServo will
look for Chrome in common locations, or you can configure `:chrome_path` / `CHROME_PATH`
explicitly.

## 📡 Telemetry

BrowseServo emits telemetry events under the `[:browse_servo, :browser, ...]` prefix for:

- runtime initialization
- capability inspection
- page creation and navigation
- content reads and evaluation
- page closure
- browser termination

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

Release flow:

1. Build all NIF archives for the configured targets.
2. Generate the checksum file included in the Hex package.
3. Update `mix.exs` and `CHANGELOG.md`.
4. Commit the release metadata and push the release branch plus `v<version>` atomically.
5. Publish the Hex package.
6. Create the GitHub release with the built NIF archives.

## 📄 License

MIT
