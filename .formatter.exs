[
  import_deps: [:quokka],
  inputs: ~w[
    {mix,.formatter,.credo}.exs
    {config,lib,test}/**/*.{ex,exs}
  ],
  plugins: [Quokka]
]
