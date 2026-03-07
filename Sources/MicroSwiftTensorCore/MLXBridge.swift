import MLX

@inline(__always)
func withMLXCPU<R>(_ body: () -> R) -> R {
  return Device.withDefaultDevice(.cpu, body)
}
