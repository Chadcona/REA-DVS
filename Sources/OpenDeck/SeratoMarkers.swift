import Foundation

struct CuePoint: Codable, Hashable, Identifiable {
    let index: Int
    let positionMilliseconds: UInt32
    let name: String
    let colorHex: String

    var id: Int { index }
    var position: TimeInterval { TimeInterval(positionMilliseconds) / 1_000 }
}

enum SeratoMarkers {
    static func readCuePoints(from url: URL) -> [CuePoint] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let filePrefix = try? handle.read(upToCount: 2 * 1_024 * 1_024),
              let label = filePrefix.range(of: Data("Serato Markers2\0".utf8))
        else { return [] }
        let payload = filePrefix.suffix(from: label.upperBound)
        return parse(payload: Data(payload))
    }

    static func parse(payload: Data) -> [CuePoint] {
        guard payload.count >= 4, payload[0] == 1, payload[1] == 1 else { return [] }
        let encoded = payload.dropFirst(2).prefix { $0 != 0 }
            .filter { $0 != 10 && $0 != 13 && $0 != 32 }
        var base64 = Data(encoded)
        while base64.count % 4 != 0 { base64.append(65) } // Serato occasionally omits padding.
        guard let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), decoded.count >= 2 else { return [] }

        var offset = 2
        var cues: [CuePoint] = []
        while offset < decoded.count,
              let terminator = decoded[offset...].firstIndex(of: 0), terminator > offset,
              terminator + 4 < decoded.count {
            let type = String(data: decoded[offset..<terminator], encoding: .ascii) ?? ""
            let lengthStart = terminator + 1
            let length = be32(decoded, at: lengthStart)
            let bodyStart = lengthStart + 4
            let bodyEnd = bodyStart + Int(length)
            guard bodyEnd <= decoded.count else { break }
            if type == "CUE", let cue = decodeCue(Data(decoded[bodyStart..<bodyEnd])) { cues.append(cue) }
            offset = bodyEnd
        }
        return cues.sorted { $0.index < $1.index }
    }

    private static func decodeCue(_ body: Data) -> CuePoint? {
        guard body.count >= 12 else { return nil }
        let nameEnd = body[12...].firstIndex(of: 0) ?? body.endIndex
        let name = String(data: body[12..<nameEnd], encoding: .utf8) ?? ""
        return CuePoint(
            index: Int(body[1]),
            positionMilliseconds: be32(body, at: 2),
            name: name,
            colorHex: String(format: "#%02X%02X%02X", body[7], body[8], body[9])
        )
    }

    private static func be32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
