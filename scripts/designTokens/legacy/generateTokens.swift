import Foundation

struct Token: CustomStringConvertible {
    let name: String
    let type: String
    let value: Any

    var description: String {
        "Token(\n\tname: \(name),\n\ttype: \(type),\n\tvalue: \(value)\n)"
    }
}

let tab = "    "
var outputTokens: [Token] = []

public func start() {
    let defaultFileName = "tokens.json"
    var inputFileName = CommandLine.arguments.count > 1 ? String(CommandLine.arguments[1]) : defaultFileName
    let isDebugMode = CommandLine.arguments.last == "-debug"
    inputFileName = inputFileName == "-debug" ? defaultFileName : inputFileName

    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = currentDirectoryURL.appendingPathComponent(inputFileName)

    let inputDictionary = readJSONFromFile(url: fileURL)

    // this dictionary will store all values including resolved references
    var lookupDictionary: [String: Any] = [:]

    // populate lookup dictionary
    parseDictionary(
        input: inputDictionary,
        lookup: &lookupDictionary
    )

    // create a new json dictionary with all the references resolved
    let resolvedDictionary = resolveReferences(
        dictionary: inputDictionary,
        using: &lookupDictionary
    )

    // clear existing tokens
    outputTokens = []

    // generate new tokens
    generateTokens(from: resolvedDictionary, using: &lookupDictionary)

    if isDebugMode {
        for (index, token) in outputTokens.enumerated() {
            print("\(index + 1): \(token)")
        }

        // for debugging
        writeJson(dictionary: resolvedDictionary, fileName: "resolved.json")
    }

    print("✅ Total \(outputTokens.count) tokens parsed.")
    generateColorPrimitives()
    generateColorSemantics()
    generateSpacing()
    generateSizing()
    generateRadius()
    generateTypography()
    generateElevation()
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

/// creates a lookup dictonary of all token vakues  including resolved reference values
private func parseDictionary(
    input: [String: Any],
    parentKeys: [String] = [],
    lookup: inout [String: Any]
) {
    var parsedDictionary = [String: Any]()

    for (key, value) in input {
        if let nestedDictionary = value as? [String: Any] {
            // If the value is a dictionary, recursively parse it
            let nestedParentKeys = parentKeys + [key]
            parsedDictionary[key] = parseDictionary(
                input: nestedDictionary,
                parentKeys: nestedParentKeys,
                lookup: &lookup
            )
        } else {
            // If the value is not a dictionary, add it directly, with concatenated parent keys
            if key == "value" {
                if let stringValue = value as? String,
                   stringValue.hasPrefix("{"),
                   stringValue.hasSuffix("}")
                {
                    continue
                } else {
                    let concatenatedKey = parentKeys.filter { $0.lowercased() != "global" }.joined(separator: ".")
                    parsedDictionary[concatenatedKey] = value
                    lookup[concatenatedKey] = value
                }
            } else {
                continue
            }
        }
    }
}

/// creates token objects
private func generateTokens(
    from dictionary: [String: Any],
    using lookup: inout [String: Any],
    parentKeys: [String] = [],
    type: String = ""
) {
    var parsedDictionary = [String: Any]()

    for (key, value) in dictionary {
        if let nestedDictionary = value as? [String: Any],
           key != "value" // this condition handles tokens for typography and boxshadow
        {
            // value is a dictionary, recursively parse it
            let nestedParentKeys = parentKeys + [key]
            if let currentType = nestedDictionary["type"] as? String {
                parsedDictionary[key] = generateTokens(
                    from: nestedDictionary,
                    using: &lookup,
                    parentKeys: nestedParentKeys,
                    type: currentType
                )
            } else {
                parsedDictionary[key] = generateTokens(
                    from: nestedDictionary,
                    using: &lookup,
                    parentKeys: nestedParentKeys
                )
            }
        } else {
            // value is not a dictionary,
            // If key is a "value", then create the Token
            if key == "value" {
                let concatenatedKey = parentKeys.filter { $0.lowercased() != "global" }.joined(separator: ".")
                outputTokens.append(.init(name: concatenatedKey, type: type, value: value))
                lookup[concatenatedKey] = value
            } else {
                continue
            }
        }
    }
}

/// resolves all references using a lookup dictionary
private func resolveReferences(
    dictionary: [String: Any],
    using lookup: inout [String: Any]
) -> [String: Any] {
    var resolvedDictionary = [String: Any]()

    for (key, value) in dictionary {
        if let nestedDictionary = value as? [String: Any] {
            // skip resolving colors
            if nestedDictionary["type"] as? String == "color" {
                resolvedDictionary[key] = value
                continue
            }

            // If the value is a dictionary, recursively parse it
            resolvedDictionary[key] = resolveReferences(
                dictionary: nestedDictionary,
                using: &lookup
            )
        } else {
            // If the value is not a dictionary,
            // if we are parsing a reference then resolve the reference using flatDictionary
            if let reference = value as? String,
               reference.hasPrefix("{"),
               reference.hasSuffix("}")
            {
                let referenceKey = reference
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                if let resolvedValue = lookup[referenceKey] {
                    resolvedDictionary[key] = resolvedValue
                } else {
                    print("⚠️ UnknownReferenceError: \"\(referenceKey)\" Key not found")
                    resolvedDictionary[key] = value
                }
            } else {
                resolvedDictionary[key] = value
            }
        }
    }

    return resolvedDictionary
}

/// Parse color tokens and generates color assets for premitive colors
private func generateColorPrimitives() {
    let colorTokens = outputTokens
        .filter { $0.type == "color" && $0.name.hasPrefix("Primitives") }
        .sorted(by: { $0.name < $1.name })
    guard !colorTokens.isEmpty else {
        print("⚠️ No Primitive Color tokens were found")
        return
    }

    for colorToken in colorTokens {
        if let parsedName = parseColor(
            colorToken.name,
            from: "Primitives",
            isVariableName: false
        ),
            let hexColor = colorToken.value as? String,
            let (red, green, blue, alpha) = hexToHexRGBAlphaString(hex: hexColor)
        {
            let filePath = getPathForGeneratedColorsets().appending(
                component: "\(parsedName).colorset"
            )
            let tab = "  " // Xcode generated json file uses 2 spaces for tab
            var jsonCode = "{\n\(tab)\"colors\" : [\n\(tab)\(tab){\n\(tab)\(tab)\(tab)"
            jsonCode += "\"color\" : {\n\(tab)\(tab)\(tab)\(tab)\"color-space\" : \"srgb\",\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)\"components\" : {\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)\(tab)\"alpha\" : \"\(alpha)\",\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)\(tab)\"blue\" : \"\(blue)\",\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)\(tab)\"green\" : \"\(green)\",\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)\(tab)\"red\" : \"\(red)\"\n"
            jsonCode += "\(tab)\(tab)\(tab)\(tab)}\n\(tab)\(tab)\(tab)},\n"
            jsonCode += "\(tab)\(tab)\(tab)\"idiom\" : \"universal\"\n"
            jsonCode += "\(tab)\(tab)}\n\(tab)],\n\(tab)\"info\" : {\n\(tab)\(tab)"
            jsonCode += "\"author\" : \"xcode\",\n\(tab)\(tab)\"version\" : 1\n\(tab)}\n}\n"
            writeToFile(content: jsonCode, filePath: filePath, fileName: "Contents.json")
        }
    }
}

/// Parse color tokens and generates a swift file referencing premitive tokens
private func generateColorSemantics() {
    let colorTokens = outputTokens
        .filter { $0.type == "color" }
        .sorted(by: { $0.name < $1.name })
    guard !colorTokens.isEmpty else {
        print("⚠️ No Color tokens were found")
        return
    }

    var swiftCode = "import SwiftUI\n\npublic extension Color {"
    var lightModeMap: [String: String] = [:]
    var darkModeMap: [String: String] = [:]
    for token in colorTokens {
        if let parsedName = parseColor(token.name, from: "Light Mode", isVariableName: true) {
            if let tokenValue = token.value as? String {
                var trimmedTokenValue = tokenValue.replacingOccurrences(of: "{", with: "")
                trimmedTokenValue = trimmedTokenValue.replacingOccurrences(of: "}", with: "")
                if let parsedValue = parseColor(trimmedTokenValue, from: "Primitives", isVariableName: false) {
                    lightModeMap[parsedName] = parsedValue
                }
            }
        }
        if let parsedName = parseColor(token.name, from: "Dark Mode", isVariableName: true) {
            if let tokenValue = token.value as? String {
                var trimmedTokenValue = tokenValue.replacingOccurrences(of: "{", with: "")
                trimmedTokenValue = trimmedTokenValue.replacingOccurrences(of: "}", with: "")
                if let parsedValue = parseColor(trimmedTokenValue, from: "Primitives", isVariableName: false) {
                    darkModeMap[parsedName] = parsedValue
                }
            }
        }
    }
    for (key, value) in lightModeMap.sorted(by: { $0.0 < $1.0 }) {
        var newLineSwiftCode = "\n\(tab)static var \(key): Color {\n\(tab)\(tab)colorPrimitive(\"\(value)\""
        if let darkModeValue = darkModeMap[key] {
            newLineSwiftCode += ", darkMode: \"\(darkModeValue)\""
        }
        swiftCode += "\(newLineSwiftCode))\n\(tab)}\n"
    }
    swiftCode += "}\n"

    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "Color+Semantic.swift"
    )
}

private func generateSpacing() {
    let spacingTokens = outputTokens
        .filter { $0.type == "spacing" }
        .sorted(by: { $0.name < $1.name })
    guard !spacingTokens.isEmpty else {
        print("⚠️ No Spacing tokens were found")
        return
    }

    var swiftCode = "import UIKit\n\npublic extension CGFloat {"
    for token in spacingTokens {
        let snakecaseTokenName = token.name
            .components(separatedBy: ".")
            .joined(separator: "_").replacingOccurrences(of: "-", with: "_")
        let parsedName = snakeCaseToCamelCase(snakecaseTokenName)
        if let tokenValue = token.value as? String {
            var parsedValue = tokenValue
            if tokenValue.hasSuffix("px") {
                parsedValue = String(tokenValue.dropLast(2))
            }
            swiftCode += "\n\(tab)/// => \(tokenValue)"
            swiftCode += "\n\(tab)static var \(parsedName): CGFloat { \(parsedValue) }\n"
        } else {
            print("⚠️ Spacing \(parsedName) does not have a string value")
        }
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "CGFloat+Spacing.swift"
    )
}

private func generateSizing() {
    let sizingTokens = outputTokens
        .filter { $0.type == "sizing" }
        .sorted(by: { $0.name < $1.name })
    guard !sizingTokens.isEmpty else {
        print("⚠️ No Sizing tokens were found")
        return
    }

    var swiftCode = "import UIKit\n\npublic extension CGFloat {"
    for token in sizingTokens {
        let snakecaseTokenName = token.name
            .components(separatedBy: ".")
            .joined(separator: "_").replacingOccurrences(of: "-", with: "_")
        let parsedName = snakeCaseToCamelCase(snakecaseTokenName)
        if let tokenValue = token.value as? String {
            var parsedValue = tokenValue
            if tokenValue.hasSuffix("px") {
                parsedValue = String(tokenValue.dropLast(2))
            }
            swiftCode += "\n\(tab)static var \(parsedName): CGFloat { \(parsedValue) }\n"
        } else {
            print("⚠️ Sizing \(parsedName) does not have a string value")
        }
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "CGFloat+Sizing.swift"
    )
}

private func generateRadius() {
    let radiusTokens = outputTokens
        .filter { $0.type == "borderRadius" }
        .sorted(by: { $0.name < $1.name })
    guard !radiusTokens.isEmpty else {
        print("⚠️ No Radius tokens were found")
        return
    }

    var swiftCode = "import UIKit\n\npublic extension CGFloat {"
    for token in radiusTokens {
        let snakecaseTokenName = token.name
            .components(separatedBy: ".")
            .joined(separator: "_").replacingOccurrences(of: "-", with: "_")
        let parsedName = snakeCaseToCamelCase(snakecaseTokenName)
        if let tokenValue = token.value as? String {
            var parsedValue = tokenValue
            if tokenValue.hasSuffix("px") {
                parsedValue = String(tokenValue.dropLast(2))
            }
            swiftCode += "\n\(tab)static var \(parsedName): CGFloat { \(parsedValue) }\n"
        } else {
            print("⚠️ borderRadius: \(parsedName) does not have a string value")
        }
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "CGFloat+Radius.swift"
    )
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
        guard let attributes = token.value as? [String: String],
              let fontFamily = attributes["fontFamily"],
              let fontWeight = attributes["fontWeight"],
              let fontSizeString = attributes["fontSize"],
              let lineHeightString = attributes["lineHeight"],
              let letterSpacingString = attributes["letterSpacing"],
              let fontSize = Double(fontSizeString),
              let lineHeight = Double(lineHeightString),
              let letterSpacing = Double(letterSpacingString.replacingOccurrences(of: "%", with: ""))
        else {
            print("⚠️ Typography attribute could not be parsed: \(token)")
            return
        }

        let tokenName = token.name.replacingOccurrences(of: "-", with: "")

        swiftCode += "\n\(tab)static let \(tokenName): TextStyle = .init("
        swiftCode += "\n\(tab)\(tab)fontNameAndWeight: \"\(fontFamily)-\(fontWeight)\","
        swiftCode += "\n\(tab)\(tab)fontSize: \(fontSize),"
        swiftCode += "\n\(tab)\(tab)lineHeight: \(lineHeight),"
        swiftCode += "\n\(tab)\(tab)letterSpacing: \(letterSpacing)\n\(tab))\n"
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
        guard let attributes = token.value as? [String: String],
              let colorString = attributes["color"],
              let (_, _, _, alpha) = hexToRGBA(hex: colorString),
              let x = attributes["x"],
              let y = attributes["y"],
              let blurRadius = attributes["blur"]
        else {
            print("⚠️ boxShadow attributes could not be parsed: \(token)")
            return
        }
        let tokenName = token.name.replacingOccurrences(of: "-", with: "").lowercased()
        swiftCode += "\n\(tab)static let \(tokenName): ElevationStyle = .init("
        swiftCode += "\n\(tab)\(tab)blurRadius: \(blurRadius),"
        swiftCode += "\n\(tab)\(tab)x: \(x),"
        swiftCode += "\n\(tab)\(tab)y: \(y),"
        swiftCode += "\n\(tab)\(tab)opacity: \(String(format: "%.2f", alpha))"
        swiftCode += "\n\(tab))\n"
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "ElevationStyle+Primitive.swift"
    )
}

// parse Anything.NameSpace.ColorParent.Color.Specific to "colorparent_color_specific",
// where NameSpace is either "Primitives" or "Semantic"
// isVaribaleName: if the token name is a swiftVariable then convert to camelCase
private func parseColor(
    _ tokenName: String,
    from namespace: String,
    isVariableName: Bool
) -> String? {
    if tokenName.contains(namespace) {
        let nameElements: [String] = tokenName.components(separatedBy: ".").map { $0.lowercased() }
        let semanticIndex = nameElements.firstIndex(of: namespace.lowercased())! + 1
        let parsedName = nameElements[semanticIndex ..< nameElements.count]
        if isVariableName {
            let snakecaseTokenName = parsedName.joined(separator: "_").replacingOccurrences(of: "-", with: "_")
            return snakeCaseToCamelCase(snakecaseTokenName)
        } else {
            return parsedName.joined(separator: "-")
        }
    } else {
        return nil
    }
}

/// Pretty prints the dictionary into a JSON format
private func prettyPrint(_ dictionary: [String: Any]) {
    let jsonData = try! JSONSerialization.data(
        withJSONObject: dictionary,
        options: JSONSerialization.WritingOptions.prettyPrinted
    )

    let jsonString = NSString(
        data: jsonData,
        encoding: String.Encoding.utf8.rawValue
    )! as String

    print("-start------------------------------------")
    print(jsonString)
    print("-end--------------------------------------")
}

/// writes dictionanry into a json file.
private func writeJson(dictionary: [String: Any], fileName: String) {
    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = currentDirectoryURL.appendingPathComponent(fileName)

    // Convert dictionary to JSON data
    // Write the content to the file
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted])
        try jsonData.write(to: fileURL)
        print("🗞️  File created successfully at: \(fileURL)")
    } catch {
        print("⚠️ Error writing file: \(error)")
    }
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

private func getPathForGeneratedColorsets() -> URL {
    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = currentDirectoryURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(components: "Libraries", "SharedUI", "Sources", "SharedUI",
                   "Resources", "Assets.xcassets", "Colors")
    return fileURL
}

private func snakeCaseToCamelCase(_ snakeCaseString: String) -> String {
    let components = snakeCaseString.components(separatedBy: "_")

    let camelCaseString = components.enumerated().reduce("") { result, pair -> String in
        let (index, component) = pair
        if index == 0 { return component }
        else {
            let capitalizedComponent = component.prefix(1).uppercased() + component.dropFirst()
            return result + capitalizedComponent
        }
    }

    return camelCaseString
}

private func hexToRGBA(hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    let hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let scanner = Scanner(string: hexString)
    var hexValue: UInt64 = 0

    guard scanner.scanHexInt64(&hexValue) else { return nil }

    switch hexString.count {
    case 6:
        return (
            CGFloat((hexValue & 0xFF0000) >> 16) / 255.0,
            CGFloat((hexValue & 0x00FF00) >> 8) / 255.0,
            CGFloat(hexValue & 0x0000FF) / 255.0,
            1.0
        )
    case 8:
        return (
            CGFloat((hexValue & 0xFF00_0000) >> 24) / 255.0,
            CGFloat((hexValue & 0x00FF_0000) >> 16) / 255.0,
            CGFloat((hexValue & 0x0000_FF00) >> 8) / 255.0,
            CGFloat(hexValue & 0x0000_00FF) / 255.0
        )
    default:
        return nil
    }
}

func hexToHexRGBAlphaString(hex: String) -> (r: String, g: String, b: String, a: String)? {
    var hexValue = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    var alpha = 1.0

    // Check if the hex string includes alpha value
    if hexValue.count == 8 {
        let alphaHex = String(hexValue.suffix(2))
        alpha = Double(strtoul(alphaHex, nil, 16)) / 255.0
        hexValue = String(hexValue.dropLast(2))
    }

    guard Scanner(string: hexValue).scanHexInt64(&rgb) else { return nil }

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0

    let redHex = String(format: "0x%02X", Int(red * 255))
    let greenHex = String(format: "0x%02X", Int(green * 255))
    let blueHex = String(format: "0x%02X", Int(blue * 255))
    let alphaFormatted = String(format: "%.3f", alpha)
    return (redHex, greenHex, blueHex, alphaFormatted)
}

// Call the start function to run the script
start()
