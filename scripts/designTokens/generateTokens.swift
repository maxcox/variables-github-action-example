import Foundation

let tab = "    "
var outputTokens: [Token] = []

public func start() {
    let publishedFileName = "tokens/tokens_published.json"
    let localFileName = "tokens/tokens_local.json"

    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let localFileURL = currentDirectoryURL.appendingPathComponent(localFileName)
    let publishedFileURL = currentDirectoryURL.appendingPathComponent(publishedFileName)

    let localFileDictionary = readJSONFromFile(url: localFileURL)
    let publishedFileDictionary = readJSONFromFile(url: publishedFileURL)

    var publishedVariableCollectionIds: [String] = []

    if let publishedMeta = publishedFileDictionary["meta"] as? [String: Any] {
        if let publishedVariableCollections = publishedMeta["variableCollections"] as? [String: Any] {
            publishedVariableCollectionIds.append(contentsOf: publishedVariableCollections.keys)
        }
    }

    var modes: Set<LocalVariableCollection.Mode> = []
    var variableTable: [String: LocalVariable] = [:]
    var variables: [LocalVariable] = []
    var variableIds: [String] = []

    if let localMeta = localFileDictionary["meta"] as? [String: Any] {
        for publishedVariableCollectionId in publishedVariableCollectionIds {
            if let localVariableCollections = localMeta["variableCollections"] as? [String: Any],
               let localVariableCollectionDict = localVariableCollections[publishedVariableCollectionId]
            {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: localVariableCollectionDict, options: .prettyPrinted)
                    let localVariableCollection: LocalVariableCollection = try JSONDecoder().decode(LocalVariableCollection.self, from: jsonData)
                    for mode in localVariableCollection.modes {
                        modes.insert(mode)
                    }
                    variableIds.append(contentsOf: localVariableCollection.variableIds)
                } catch {
                    print(error)
                }
            }
        }

        if let localVariablesDict = localMeta["variables"] as? [String: Any] {
            for (lvk, lvv) in localVariablesDict {
                if variableIds.contains(lvk) {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: lvv, options: .prettyPrinted)
                        let localVariableInfo: LocalVariableInfo = try JSONDecoder().decode(LocalVariableInfo.self, from: jsonData)
                        let localVariable = LocalVariable(
                            variableInfo: localVariableInfo,
                            valuesByMode: (lvv as? [String: Any])?["valuesByMode"] as? [String: Any] ?? [:]
                        )
                        variableTable[lvk] = localVariable
                        variables.append(localVariable)
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }

    let colorVariables = variables.filter { $0.variableInfo.resolvedType == "COLOR" }
    parseColorVariablesIntoTokens(colorVariables, with: modes)

    let floatVariables = variables.filter { $0.variableInfo.resolvedType == "FLOAT" }
    parseFloatVariablesIntoTokens(floatVariables, with: modes)

    generateColorPrimitives()
    generateRawColorSemantics()
    generateColorSemantics()
    generateValueFloats("Spacing", includeUnits: true)
    generateValueFloats("Size")
    generateValueFloats("Radius")

    print("✅ \(outputTokens.count) variable tokens parsed.")
}

private func parseColorVariablesIntoTokens(_ colorVariables: [LocalVariable], with modes: Set<LocalVariableCollection.Mode>) {
    var referencingColorTokens: [ReferenceToken] = []
    var resolvedColorTokens: [String: Token] = [:]

    for colorVariable in colorVariables {
        for mode in modes {
            if let valueForMode = colorVariable.valuesByMode[mode.modeId] as? [String: Any] {
                if let referenceId = valueForMode["id"] as? String {
                    referencingColorTokens.append(
                        ReferenceToken(
                            id: colorVariable.variableInfo.id,
                            name: colorVariable.variableInfo.name,
                            type: "color",
                            modeName: mode.name,
                            referenceId: referenceId
                        )
                    )
                } else {
                    let resolvedToken = Token(
                        name: colorVariable.variableInfo.name,
                        type: "color",
                        modeName: mode.name,
                        value: valueForMode
                    )
                    resolvedColorTokens[colorVariable.variableInfo.id] = resolvedToken
                    outputTokens.append(resolvedToken)
                }
            }
        }
    }

    var loopLimit = 0
    while referencingColorTokens.count > 0, loopLimit < 1000 {
        var remainingUnresolved: [ReferenceToken] = []
        for referencingColorToken in referencingColorTokens {
            if let referencedColorToken = resolvedColorTokens[referencingColorToken.referenceId] {
                let resolvedToken = Token(
                    name: referencingColorToken.name,
                    type: referencingColorToken.type,
                    modeName: referencingColorToken.modeName,
                    value: referencedColorToken.name
                )
                resolvedColorTokens[referencingColorToken.id] = resolvedToken
                outputTokens.append(resolvedToken)
            } else {
                remainingUnresolved.append(referencingColorToken)
            }
        }
        referencingColorTokens = remainingUnresolved
        loopLimit += 1
    }
    if loopLimit >= 1000 {
        print("❌ Failed to resolve all color token references")
    }
}

private func parseFloatVariablesIntoTokens(_ floatVariables: [LocalVariable], with modes: Set<LocalVariableCollection.Mode>) {
    var referencingFloatTokens: [ReferenceToken] = []
    var resolvedFloatTokens: [String: Token] = [:]

    for floatVariable in floatVariables {
        for mode in modes {
            if let valueForMode = floatVariable.valuesByMode[mode.modeId] as? [String: Any] {
                if let referenceId = valueForMode["id"] as? String {
                    referencingFloatTokens.append(
                        ReferenceToken(
                            id: floatVariable.variableInfo.id,
                            name: floatVariable.variableInfo.name,
                            type: floatTypeFromName(name: floatVariable.variableInfo.name),
                            modeName: mode.name,
                            referenceId: referenceId
                        )
                    )
                }
            } else if let floatForMode = floatVariable.valuesByMode[mode.modeId] as? Float {
                let resolvedToken = Token(
                    name: floatVariable.variableInfo.name,
                    type: floatTypeFromName(name: floatVariable.variableInfo.name),
                    modeName: mode.name,
                    value: floatForMode
                )
                resolvedFloatTokens[floatVariable.variableInfo.id] = resolvedToken
                outputTokens.append(resolvedToken)
            }
        }
    }

    var loopLimit = 0
    while referencingFloatTokens.count > 0, loopLimit < 1000 {
        var remainingUnresolved: [ReferenceToken] = []
        for referencingFloatToken in referencingFloatTokens {
            if let referencedFloatToken = resolvedFloatTokens[referencingFloatToken.referenceId] {
                let resolvedToken = Token(
                    name: referencingFloatToken.name,
                    type: referencingFloatToken.type,
                    modeName: referencingFloatToken.modeName,
                    value: referencedFloatToken.value
                )
                resolvedFloatTokens[referencingFloatToken.id] = resolvedToken
                outputTokens.append(resolvedToken)
            } else {
                remainingUnresolved.append(referencingFloatToken)
            }
        }
        referencingFloatTokens = remainingUnresolved

        loopLimit += 1
    }
    if loopLimit >= 1000 {
        print("❌ Failed to resolve all float token references")
    }
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

/// Parse color tokens and generates color assets for premitive colors
private func generateColorPrimitives() {
    let colorTokens = outputTokens
        .filter { $0.type == "color" && $0.name.hasPrefix("Primitives") && $0.modeName == "Light mode" }
        .sorted(by: { $0.name < $1.name })
    guard !colorTokens.isEmpty else {
        print("⚠️ No Primitive Color tokens were found")
        return
    }

    for colorToken in colorTokens {
        if let name: String = parseColorName(colorCategory: "Primitives", colorToken.name),
           let colorDictionary = colorToken.value as? [String: Float],
           let (red, green, blue, alpha) = floatToHexRGBAlphaString(colorDict: colorDictionary)
        {
            generateColorSet(name, red: red, green: green, blue: blue, alpha: alpha)
        }
    }
}

/// This parsing captures Semantic variables that have a raw value coming from Figma. This should not be happening but if it does this will capture it.
private func generateRawColorSemantics() {
    let colorTokens = outputTokens
        .filter { $0.type == "color" && $0.name.hasPrefix("Semantic") && $0.value is [String: Any] }
        .sorted(by: { $0.name < $1.name })
    guard !colorTokens.isEmpty else {
        print("No Raw Color Semantic tokens were found")
        return
    }

    for colorToken in colorTokens {
        if let name: String = parseColorName(colorCategory: "Semantic", colorToken.name),
           let colorDictionary = colorToken.value as? [String: Float],
           let (red, green, blue, alpha) = floatToHexRGBAlphaString(colorDict: colorDictionary)
        {
            let modeName = snakeCaseToCamelCase(colorToken.modeName.lowercased().replacingOccurrences(of: " ", with: "_"))
            generateColorSet(name + "-" + modeName, red: red, green: green, blue: blue, alpha: alpha)
        }
    }
}

private func generateColorSet(_ name: String, red: String, green: String, blue: String, alpha: String) {
    let filePath = getPathForGeneratedColorsets().appending(
        component: "\(name).colorset"
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

/// Parse color tokens and generates a swift file referencing premitive tokens
private func generateColorSemantics() {
    let colorTokens = outputTokens
        .filter { $0.type == "color" && $0.name.hasPrefix("Semantic") }
        .sorted(by: { $0.name < $1.name })
    guard !colorTokens.isEmpty else {
        print("⚠️ No Color tokens were found")
        return
    }

    var lightModeMap: [String: String] = [:]
    var darkModeMap: [String: String] = [:]
    for token in colorTokens {
        if let parsedSemanticKey = parseToVariableName(category: "Semantic", type: "Color", token.name), token.modeName == "Light mode" {
            if let tokenValue = token.value as? String, let parsedValue = parseColorName(colorCategory: "Primitives", tokenValue) {
                lightModeMap[parsedSemanticKey] = parsedValue
            }
            // This captures Semantic variables that have a raw value
            else if let _ = token.value as? [String: Any], let selfNameValue = parseColorName(colorCategory: "Semantic", token.name) {
                lightModeMap[parsedSemanticKey] = selfNameValue + "-lightMode"
            }
        }
        if let parsedSemanticKey = parseToVariableName(category: "Semantic", type: "Color", token.name), token.modeName == "Dark mode" {
            if let tokenValue = token.value as? String, let parsedValue = parseColorName(colorCategory: "Primitives", tokenValue) {
                darkModeMap[parsedSemanticKey] = parsedValue
            }
            // This captures Semantic variables that have a raw value
            else if let _ = token.value as? [String: Any], let selfNameValue = parseColorName(colorCategory: "Semantic", token.name) {
                darkModeMap[parsedSemanticKey] = selfNameValue + "-darkMode"
            }
        }
    }

    var swiftCode = "import SwiftUI\n\npublic extension Color {"
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

    swiftCode = "import UIKit\n\npublic extension UIColor {"
    for (key, value) in lightModeMap.sorted(by: { $0.0 < $1.0 }) {
        var newLineSwiftCode = "\n\(tab)static var \(key): UIColor {\n\(tab)\(tab)colorPrimitive(\"\(value)\""
        if let darkModeValue = darkModeMap[key] {
            newLineSwiftCode += ", darkMode: \"\(darkModeValue)\""
        }
        swiftCode += "\(newLineSwiftCode))\n\(tab)}\n"
    }
    swiftCode += "}\n"

    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "UIColor+Semantic.swift"
    )
}

private func generateValueFloats(_ categoryName: String, includeUnits: Bool = false) {
    let spacingTokens = outputTokens
        .filter { $0.type == categoryName && $0.modeName == "Light mode" }
        .sorted(by: { $0.name < $1.name })
    guard !spacingTokens.isEmpty else {
        print("⚠️ No \(categoryName) tokens were found")
        return
    }

    var swiftCode = "import UIKit\n\npublic extension CGFloat {"
    for token in spacingTokens {
        if let parsedName = parseToVariableName(category: "Semantic", type: categoryName, token.name),
           let tokenValue = token.value as? Float
        {
            let parsedValue = String(format: "%.0f", tokenValue)
            if includeUnits {
                swiftCode += "\n\(tab)/// => \(parsedValue)px"
            }
            swiftCode += "\n\(tab)static var \(parsedName): CGFloat { \(parsedValue) }\n"
        }
    }
    swiftCode += "}\n"
    writeToFile(
        content: swiftCode,
        filePath: getPathForGeneratedStyles(),
        fileName: "CGFloat+\(categoryName).swift"
    )
}

private func parseColorName(colorCategory: String, _ colorName: String) -> String? {
    var tempColorName = colorName
    tempColorName = tempColorName.replacingOccurrences(of: colorCategory + "/", with: "")
    tempColorName = tempColorName.replacingOccurrences(of: "Color" + "/", with: "")
    tempColorName = tempColorName.lowercased()
    tempColorName = tempColorName.replacingOccurrences(of: "/", with: "-")
    return tempColorName
}

private func parseToVariableName(category: String, type: String, _ name: String) -> String? {
    var tempVarName = name
    tempVarName = tempVarName.replacingOccurrences(of: category + "/", with: "")
    tempVarName = tempVarName.replacingOccurrences(of: type + "/", with: "")
    tempVarName = tempVarName.lowercased()
    tempVarName = tempVarName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "-", with: "_")
    tempVarName = snakeCaseToCamelCase(tempVarName)
    return tempVarName
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

private func floatTypeFromName(name: String) -> String {
    if name.contains("Spacing") {
        return "Spacing"
    } else if name.contains("Dimension") {
        return "Dimension"
    } else if name.contains("Size") {
        return "Size"
    } else if name.contains("Radius") {
        return "Radius"
    }

    return name
}

private func floatToHex(colorValue: Float) -> String {
    let intValue = Int(round(colorValue * 255))
    let hexValue = String(intValue, radix: 16, uppercase: true)
    return "0x\(hexValue.count < 2 ? "0" : "")\(hexValue)"
}

private func floatToHexRGBAlphaString(colorDict: [String: Float]) -> (r: String, g: String, b: String, a: String)? {
    guard let r = colorDict["r"], let g = colorDict["g"], let b = colorDict["b"], let a = colorDict["a"] else {
        return nil
    }

    let redHex = floatToHex(colorValue: r)
    let greenHex = floatToHex(colorValue: g)
    let blueHex = floatToHex(colorValue: b)
    let alphaFormatted = String(format: "%.3f", a)
    return (redHex, greenHex, blueHex, alphaFormatted)
}

// Call the start function to run the script
start()

// MARK: - Struct Definitions

struct Token: CustomStringConvertible {
    let name: String
    let type: String
    let modeName: String
    let value: Any

    var description: String {
        "Token(\n  name: \(name),\n  type: \(type),\n  modeName: \(modeName),\n  value: \(value)\n)"
    }
}

struct ReferenceToken {
    let id: String
    let name: String
    let type: String
    let modeName: String
    let referenceId: String
}

struct LocalVariableCollection: Codable {
    let defaultModeId: String
    let id: String
    let name: String
    let remote: Bool
    let modes: [Mode]
    let key: String
    let hiddenFromPublishing: Bool
    let variableIds: [String]

    enum CodingKeys: String, CodingKey {
        case defaultModeId
        case id
        case name
        case remote
        case modes
        case key
        case hiddenFromPublishing
        case variableIds
    }

    struct Mode: Codable, Hashable {
        let modeId: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case modeId
            case name
        }
    }
}

struct LocalVariable {
    let variableInfo: LocalVariableInfo
    let valuesByMode: [String: Any]
}

struct LocalVariableInfo: Codable {
    let id: String
    let name: String
    let remote: Bool
    let key: String
    let variableCollectionId: String
    let resolvedType: String
    let description: String
    let hiddenFromPublishing: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case remote
        case key
        case variableCollectionId
        case resolvedType
        case description
        case hiddenFromPublishing
    }
}
