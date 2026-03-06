# ADR 0002 — MLX runtime wrapper

MLX command usage is routed through `Scripts/mlx-run` and `xcodebuild` in order to
match the recommended command-line execution path for shader-backed binaries.
