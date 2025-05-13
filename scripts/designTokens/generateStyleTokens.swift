import Foundation

let tab = "    "
var outputTokens: [Token] = []

public func start() {
    let fileName = "tokens/tokens_styles.json"

    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = currentDirectoryURL.appendingPathComponent(fileName)

    let fileDictionary = readJSONFromFile(url: fileURL)

    var styles: [[String: Any]] = []

    if let nodes = fileDictionary["nodes"] as? [String: Any] {
        for node in nodes.values {
            if let documentValue = node as? [String: Any], let styleValue = documentValue["document"] as? [String: Any] {
                styles.append(styleValue)
            }
        }
    }

    let elevationStyles = styles.filter { ($0["name"] as? String)?.contains("Elevation") ?? false }
    for elevationStyle in elevationStyles {
        if let effects = elevationStyle["effects"] as? [Any] {
            for effect in effects {
                if let effectsDict: [String: Any] = effect as? [String: Any] {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: effectsDict, options: .prettyPrinted) {
                        if let dropShadow: ElevationDropShadow = try? JSONDecoder().decode(ElevationDropShadow.self, from: jsonData) {
                            outputTokens.append(
                                Token(
                                    name: elevationStyle["name"] as? String ?? "",
                                    type: "boxShadow",
                                    value: dropShadow
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    let textStyleWrappers = styles.filter { $0["type"] as? String == "TEXT" }
    for textStyleWrapper in textStyleWrappers {
        if let textStyleDict = textStyleWrapper["style"] as? [String: Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: textStyleDict, options: .prettyPrinted) {
                if let textStyle: TextStyle = try? JSONDecoder().decode(TextStyle.self, from: jsonData) {
                    outputTokens.append(
                        Token(
                            name: textStyleWrapper["name"] as? String ?? "",
                            type: "typography",
                            value: textStyle
                        )
                    )
                }
            }
        }
    }

    generateElevation()
    generateTypography()

    print("✅ \(outputTokens.count) style tokens parsed.")
}

/// read token's json file
private func readJSONFromFile(url: URL) -> [String: Any] {
    do {
        // Read data from the file
        let data = try Data(contentsOf: url)

        // Deserialize JSON data into a dictionary
        guard let jsonDictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("❌ Failed to convert JSON data to dictionary")
            exit(1)
        }

        return jsonDictionary
    } catch {
        print("❌ Error reading JSON file: \(error)")
        exit(1)
    }
}

private func generateTypography() {
    let typographyTokens = outputTokens
        .filter { $0.type == "typography" }
        .sorted(by: { $0.name < $1.name })
    guard !typographyTokens.isEmpty else {
        print("⚠️ No Typography tokens were found")
        return
    }

    var swiftCode = "import Foundation\n\npublic extension TextStyle {"
    for token in typographyTokens {
        guard let textStyle = token.value as? TextStyle else {
            print("⚠️ Typography attribute could not be parsed: \(token)")
            return
        }

        let tokenName = token.name.replacingOccurrences(of: "-", with: "").lowercased()

        swiftCode += "\n\(tab)static let \(tokenName): TextStyle = .init("
        swiftCode += "\n\(tab)\(tab)fontNameAndWeight: \"\(textStyle.fontFamily)-\(textStyle.fontStyle)\","
        swiftCode += "\n\(tab)\(tab)fontSize: \(textStyle.fontSize),"
        swiftCode += "\n\(tab)\(tab)lineHeight: \(textStyle.lineHeightPx),"
        swiftCode += "\n\(tab)\(tab)letterSpacing: \(textStyle.letterSpacing / textStyle.fontSize * 100)\n\(tab))\n"
    }

    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "TextStyle+Primitive.swift"
    )
}

private func generateElevation() {
    let elevationTokens = outputTokens
        .filter { $0.type == "boxShadow" }
        .sorted(by: { $0.name < $1.name })
    guard !elevationTokens.isEmpty else {
        print("⚠️ No boxShadow tokens were found")
        return
    }

    var swiftCode = "import Foundation\n\npublic extension ElevationStyle {"
    for token in elevationTokens {
        guard let dropShadow = token.value as? ElevationDropShadow else {
            print("⚠️ boxShadow attributes could not be parsed: \(token)")
            return
        }
        let tokenName = token.name.replacingOccurrences(of: "-", with: "").lowercased()
        swiftCode += "\n\(tab)static let \(tokenName): ElevationStyle = .init("
        swiftCode += "\n\(tab)\(tab)blurRadius: \(dropShadow.radius),"
        swiftCode += "\n\(tab)\(tab)x: \(dropShadow.offset.x),"
        swiftCode += "\n\(tab)\(tab)y: \(dropShadow.offset.y),"
        swiftCode += "\n\(tab)\(tab)opacity: \(String(format: "%.2f", dropShadow.color.a))"
        swiftCode += "\n\(tab))\n"
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "ElevationStyle+Primitive.swift"
    )
}

/// writes contents into a file.
private func writeToFile(content: String, filePath: URL, fileName: String) {
    // Create the output folder if it doesn't exist
    do {
        try FileManager.default.createDirectory(
            at: filePath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    } catch {
        print("⚠️ Error creating output directory: \(error)")
    }

    let fileURL = filePath.appendingPathComponent(fileName)

    // Write the content to the file
    do {
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        print("🗞️  \(fileName) created successfully at: \(fileURL)")
    } catch {
        print("⚠️ Error writing file \(fileName): \(error)")
    }
}

private func getPathForGeneratedStyles() -> URL {
    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = currentDirectoryURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(components: "Libraries", "SharedUI", "Sources", "SharedUI", "Styles", "Generated")
    return fileURL
}

// Call the start function to run the script
start()

// MARK: - Struct Definitions

struct Token: CustomStringConvertible {
    let name: String
    let type: String
    let value: Any

    var description: String {
        "Token(\n  name: \(name),\n  type: \(type),\n  value: \(value)\n)"
    }
}

struct ElevationDropShadow: Codable {
    let type: String
    let color: DropShadowColor
    let offset: DropShadowOffset
    let radius: Float

    enum CodingKeys: String, CodingKey {
        case type
        case color
        case offset
        case radius
    }

    struct DropShadowColor: Codable {
        let r: Float
        let g: Float
        let b: Float
        let a: Float

        enum CodingKeys: String, CodingKey {
            case r
            case g
            case b
            case a
        }
    }

    struct DropShadowOffset: Codable {
        let x: Float
        let y: Float

        enum CodingKeys: String, CodingKey {
            case x
            case y
        }
    }
}

struct TextStyle: Codable {
    let fontFamily: String
    let fontStyle: String
    let fontSize: Float
    let lineHeightPx: Float
    let letterSpacing: Float

    enum CodingKeys: String, CodingKey {
        case fontFamily
        case fontStyle
        case fontSize
        case lineHeightPx
        case letterSpacing
    }
}
