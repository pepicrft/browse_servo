# Servox

Servox is a Rustler-backed Elixir browser runtime for Elixir applications that want
an idiomatic browser API with a native process boundary.

The architectural boundary is:

- an Elixir `GenServer` owns the browser runtime
- Rustler NIF resources hold the native runtime state
- Elixir page/browser modules expose an idiomatic API over direct native method calls

## 🚀 Status

Servox is a working project with a production-ready release pipeline, tested Elixir
API surface, telemetry instrumentation, and precompiled NIF distribution.

What is included today:

- package/app identity as `servox`
- Rustler-based native crate under `native/servox_native`
- `Servox.Browser` as the Elixir process boundary
- `Servox.Page` as the high-level page handle
- telemetry events for browser lifecycle and page operations
- precompiled-NIF publishing setup via `rustler_precompiled`
- tests, docs, formatting, and CI scaffolding

Current implementation notes:

- the native layer currently uses an in-memory browser model while the Servo embedding evolves
- the public Elixir API is stable and designed to carry forward to the Servo-backed runtime

## 📦 Installation

```elixir
def deps do
  [
    {:servox, "~> 0.1.0-dev"}
  ]
end
```

For development in this repository:

```bash
mise install
mix setup
```

## 🧭 Usage

### Start a browser runtime

```elixir
{:ok, browser} = Servox.start_link()
```

### Open and use a page

```elixir
{:ok, page} = Servox.Browser.new_page(browser, url: "https://example.com")
{:ok, page} = Servox.Page.goto(page, "https://example.com/docs")
{:ok, title} = Servox.Page.title(page)
{:ok, html} = Servox.Page.content(page)
{:ok, value} = Servox.Page.evaluate(page, "document.title")
```

### Inspect runtime capabilities

```elixir
{:ok, caps} = Servox.Browser.capabilities(browser)
```

## 🧩 Native Layer

`Servox.Native` uses `RustlerPrecompiled`, so published releases can ship precompiled NIFs and
downstream users do not need Rust installed.

During local development the `0.1.0-dev` version force-builds the NIF from source.

## 📡 Telemetry

Servox emits telemetry events under the `[:servox, :browser, ...]` prefix for:

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
