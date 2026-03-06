import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct BridgeVerificationTests {
  @Test
  func byteToClassBridgeMapsAsciiDigitsToSingleDigitClass() throws {
    let runtime = try makeMicroSwiftRuntime()
    let digitBytes = asciiRange("0", "9")
    let byteToClassLUT = runtime.hostByteToClassLUT()

    let digitClassID = UInt8(truncatingIfNeeded: byteToClassLUT[Int(digitBytes[0])])

    for byte in digitBytes {
      #expect(UInt8(truncatingIfNeeded: byteToClassLUT[Int(byte)]) == digitClassID)
    }

    let digitClassDecl = try #require(runtime.classes.first { $0.classID == digitClassID })
    for byte in digitBytes {
      #expect(digitClassDecl.bytes.contains(byte))
    }
  }

  @Test
  func classSetMembershipIncludesDigitsAndIdentifierStartLetters() throws {
    let runtime = try makeMicroSwiftRuntime()
    let byteToClassLUT = runtime.hostByteToClassLUT()

    let digitSetID = try classSetID(for: ByteSet.asciiDigit, runtime: runtime)
    let identStartSetID = try classSetID(for: ByteSet.asciiIdentStart, runtime: runtime)

    let digitClassIDs = Set(asciiRange("0", "9").map { UInt8(truncatingIfNeeded: byteToClassLUT[Int($0)]) })
    for classID in digitClassIDs {
      #expect(runtime.classSetRuntime.contains(setID: digitSetID, classID: classID))
    }

    let letterClassIDs = Set(
      (asciiRange("A", "Z") + asciiRange("a", "z")).map { UInt8(truncatingIfNeeded: byteToClassLUT[Int($0)]) })
    for classID in letterClassIDs {
      #expect(runtime.classSetRuntime.contains(setID: identStartSetID, classID: classID))
    }
  }

  @Test
  func classificationIsDeterministicForSameBytesAndArtifact() throws {
    let runtime = try makeMicroSwiftRuntime()
    let sample = Array("let x1 = foo42 + 9\\n".utf8) + Array(UInt8.min...UInt8.max)
    let byteToClassLUT = runtime.hostByteToClassLUT()

    let first = ByteClassifier.classify(bytes: sample, byteToClassLUT: byteToClassLUT)
    let second = ByteClassifier.classify(bytes: sample, byteToClassLUT: byteToClassLUT)

    #expect(first == second)
  }

  @Test
  func allByteValuesMapToDeclaredClass() throws {
    let runtime = try makeMicroSwiftRuntime()
    let allBytes = Array(UInt8.min...UInt8.max)
    let classIDs = ByteClassifier.classify(
      bytes: allBytes,
      byteToClassLUT: runtime.hostByteToClassLUT()
    )
    let declaredClassIDs = Set(runtime.classes.map(\.classID))

    #expect(classIDs.count == 256)
    for classID in classIDs {
      #expect(declaredClassIDs.contains(classID))
    }
  }

  @Test
  func classSetMembershipIsConsistentForAllBytes() throws {
    let runtime = try makeMicroSwiftRuntime()
    let allBytes = Array(UInt8.min...UInt8.max)
    let classIDs = ByteClassifier.classify(
      bytes: allBytes,
      byteToClassLUT: runtime.hostByteToClassLUT()
    )

    let bytesByClassID = Dictionary(
      uniqueKeysWithValues: runtime.classes.map { ($0.classID, Set($0.bytes)) })

    for set in runtime.classSets {
      let kernelMask = MembershipKernels.membershipMask(
        classIDs: classIDs,
        setID: set.classSetID.rawValue,
        classSetRuntime: runtime.classSetRuntime
      )

      var byteMembership = Array(repeating: false, count: 256)
      for classID in set.classes {
        guard let members = bytesByClassID[classID] else { continue }
        for byte in members {
          byteMembership[Int(byte)] = true
        }
      }

      for byte in allBytes {
        #expect(kernelMask[Int(byte)] == byteMembership[Int(byte)])
      }
    }
  }

  @Test
  func boundaryBytesAndEmptyInputClassification() throws {
    let runtime = try makeMicroSwiftRuntime()
    let byteToClassLUT = runtime.hostByteToClassLUT()

    let zeroClass = ByteClassifier.classify(bytes: [0x00], byteToClassLUT: byteToClassLUT)
    #expect(zeroClass.count == 1)
    #expect(runtime.classes.contains { $0.classID == zeroClass[0] })

    let ffClass = ByteClassifier.classify(bytes: [0xFF], byteToClassLUT: byteToClassLUT)
    #expect(ffClass.count == 1)
    #expect(runtime.classes.contains { $0.classID == ffClass[0] })

    let empty = ByteClassifier.classify(bytes: [], byteToClassLUT: byteToClassLUT)
    #expect(empty.isEmpty)
  }

  private func makeMicroSwiftRuntime() throws -> ArtifactRuntime {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)
    let validated = try NormalizedSpec.validate(normalized)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)

    let artifact = try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "test"
    )

    return try ArtifactLoader.load(artifact)
  }

  private func classSetID(for byteSet: ByteSet, runtime: ArtifactRuntime) throws -> UInt16 {
    let byteToClassLUT = runtime.hostByteToClassLUT()
    let projected = Set(byteSet.members.map { UInt8(truncatingIfNeeded: byteToClassLUT[Int($0)]) })
    let set = try #require(runtime.classSets.first { Set($0.classes) == projected })
    return set.classSetID.rawValue
  }

  private func asciiRange(_ start: Character, _ end: Character) -> [UInt8] {
    let lower = UInt8(String(start).utf8.first!)
    let upper = UInt8(String(end).utf8.first!)
    return Array(lower...upper)
  }
}
