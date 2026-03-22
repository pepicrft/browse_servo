# Lightpanda

Elixir-native wrapper around the [Lightpanda browser](https://github.com/lightpanda-io/browser).

This project is designed around three goals:

- expose a small, Elixir-style API over Lightpanda's CLI and CDP surface
- manage Lightpanda browser binaries for consumers automatically
- use Zigler for the native platform helpers while publishing precompiled NIFs so end users do not need Zig installed

## Status

This repository is scaffolded as a draft release candidate. The package version is currently `0.1.0-dev`, which means the Zigler native helper is force-built locally during development. The release workflow included here is what turns the native helper into precompiled artifacts for published versions.

## Installation

Add `lightpanda` to your dependencies:

```elixir
def deps do
  [
    {:lightpanda, "~> 0.1.0-dev"}
  ]
end
```

For local development on this repository:

```bash
mise install
mix setup
```

Consumers of a published release only need Erlang/Elixir. The Lightpanda browser binary itself is downloaded on demand from the upstream `lightpanda-io/browser` nightly release unless you point the library at a custom executable.

## Usage

### Fetch rendered HTML

```elixir
{:ok, result} =
  Lightpanda.fetch("https://example.com",
    dump: :html,
    obey_robots: true,
    wait_until: :networkidle
  )

result.output
```

### Launch a managed browser server

```elixir
{:ok, browser} =
  Lightpanda.launch(
    obey_robots: true,
    timeout: 30,
    log_level: :info
  )

{:ok, page} = Lightpanda.Browser.new_page(browser)
{:ok, page} = Lightpanda.Page.goto(page, "https://example.com")
{:ok, title} = Lightpanda.Page.evaluate(page, "document.title")
```

### Browser contexts and pages

```elixir
{:ok, context} = Lightpanda.Browser.new_context(browser)
{:ok, page} = Lightpanda.Browser.new_page(browser, context: context)

{:ok, _page} = Lightpanda.Page.fill(page, "input[name=q]", "lightpanda")
{:ok, _page} = Lightpanda.Page.click(page, "button[type=submit]")
{:ok, html} = Lightpanda.Page.content(page)
```

### Cookies, headers, and interception

```elixir
{:ok, _page} =
  Lightpanda.Page.set_extra_http_headers(page, %{
    "x-from-elixir" => "true"
  })

{:ok, cookies} = Lightpanda.Page.cookies(page)

{:ok, _page} = Lightpanda.Page.enable_request_interception(page)

receive do
  {:lightpanda_cdp_event, "Fetch.requestPaused", params, ^page.session_id} ->
    Lightpanda.Page.continue_request(page, params["requestId"])
end
```

### MCP mode

```elixir
{:ok, port} = Lightpanda.mcp(obey_robots: true)
```

## API Overview

- `Lightpanda.fetch/2` wraps the CLI fetch workflow and returns a `%Lightpanda.FetchResult{}`
- `Lightpanda.version/1` resolves and executes the managed Lightpanda binary
- `Lightpanda.launch/1` starts a managed `serve` process and connects CDP automatically
- `Lightpanda.Browser` manages contexts and pages
- `Lightpanda.Page` exposes high-level navigation, DOM, form, cookie, header, evaluation, and network interception helpers
- `Lightpanda.mcp/1` starts Lightpanda in MCP mode for stdio-based integrations

## Configuration

```elixir
config :lightpanda,
  binary_release: "nightly"
```

Runtime options support:

- `:binary_path` to bypass downloads and use an explicit executable
- `:binary_release` to pin a different Lightpanda GitHub release tag
- common Lightpanda flags such as `:obey_robots`, `:http_proxy`, `:user_agent_suffix`, `:log_level`, and `:log_format`

## Native Layer

`Lightpanda.Native` uses `:zigler_precompiled`. Published releases are expected to ship precompiled NIFs for the supported targets through GitHub Releases. During local development, the prerelease version forces a local Zig build.

The Zig NIF is intentionally small. It only provides platform-sensitive helpers like target detection and executable mode, while all browser logic remains in Elixir.

## Releasing

The repository ships:

- `git-cliff` configuration in [`cliff.toml`](cliff.toml)
- a CI workflow for test and lint checks
- a release workflow that generates the changelog and builds precompiled Zigler NIF artifacts

Before the first Hex release, generate and commit the checksum file for `Lightpanda.Native`:

```bash
mix zigler_precompiled.download Lightpanda.Native --all --print
```

## License

MIT
