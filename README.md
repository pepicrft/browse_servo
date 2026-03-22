# Servox

Servox is a Rustler-backed Elixir browser runtime scaffold intended to grow into a
Servo-powered browser integration.

The architectural boundary is:

- an Elixir `GenServer` owns the browser runtime
- Rustler NIF resources hold the native runtime state
- Elixir page/browser modules expose an idiomatic API over direct native method calls

## Status

This is a draft scaffold, not a complete Servo embedding yet.

What is implemented already:

- package/app identity as `servox`
- Rustler-based native crate under `native/servox_native`
- `Servox.Browser` as the Elixir process boundary
- `Servox.Page` as the high-level page handle
- precompiled-NIF publishing setup via `rustler_precompiled`
- tests, docs, formatting, and CI scaffolding

What is intentionally still a scaffold:

- the Rust crate currently uses an in-memory browser model rather than linking Servo yet
- the public API shape is meant to survive the future Servo integration

## Installation

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

## Usage

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

## Native Layer

`Servox.Native` uses `RustlerPrecompiled`, so published releases can ship precompiled NIFs and
downstream users do not need Rust installed.

During local development the `0.1.0-dev` version force-builds the NIF from source.

## Releasing

The repository includes:

- `git-cliff` configuration in `cliff.toml`
- CI checks for tests, warning-free compilation, and formatting
- a release workflow scaffold for publishing precompiled Rustler NIFs

Before the first real Hex release, generate and commit the checksum file:

```bash
mix rustler_precompiled.download Servox.Native --all --print
```

## License

MIT
