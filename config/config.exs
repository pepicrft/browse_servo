import Config

config :lightpanda,
  binary_release: "nightly",
  cdp_timeout: 5_000,
  http_client: Lightpanda.HTTP,
  native_module: Lightpanda.Native,
  runner: Lightpanda.Runner
