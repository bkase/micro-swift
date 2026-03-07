import MLX

public enum MembershipKernels {
  /// For each position, check if its classID belongs to the given ClassSet.
  /// Returns a boolean mask [P].
  public static func membershipMask(
    classIDs: [UInt8],
    setID: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> [Bool] {
    classIDs.map { classSetRuntime.contains(setID: setID, classID: $0) }
  }

  /// Precompute multiple membership masks at once (for commonly needed sets).
  public static func precomputeMasks(
    classIDs: [UInt8],
    setIDs: [UInt16],
    classSetRuntime: ClassSetRuntime
  ) -> [[Bool]] {
    setIDs.map { setID in
      membershipMask(classIDs: classIDs, setID: setID, classSetRuntime: classSetRuntime)
    }
  }

  /// MLX tensor membership: gather from the flat mask table.
  /// classIDTensor is [P] of uint16, returns [P] of bool.
  public static func membershipMaskTensor(
    classIDTensor: MLXArray,
    setID: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> MLXArray {
    let maskRow = classSetRuntime.mlxMask()[Int(setID)]
      return maskRow.take(classIDTensor.asType(.int32)).asType(.bool)
  }
}
