[
  import_deps: [:quokka, :zigler],
  inputs: ~w[
    {mix,.formatter,.credo}.exs
    {config,lib,native,test}/**/*.{ex,exs,zig}
  ],
  plugins: [Quokka, Zig.Formatter]
]
