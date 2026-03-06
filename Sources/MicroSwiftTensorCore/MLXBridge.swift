import MLX

@inline(__always)
func withMLXCPU<R>(_ body: () -> R) -> R {
  Device.withDefaultDevice(.cpu, body)
}
