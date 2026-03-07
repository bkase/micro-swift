import Cmlx
import Foundation
import MLX

/// Toggle this to `.gpu` to run MLX operations on the GPU.
public nonisolated(unsafe) var mlxDefaultDevice: Device = .cpu

@inline(__always)
func withMLXCPU<R>(_ body: () -> R) -> R {
  return Device.withDefaultDevice(mlxDefaultDevice, body)
}
