#!/usr/bin/env xcrun --sdk macosx swift

import Foundation

class EmojiGenerator {
    // from http://stackoverflow.com/a/31480534/255489
    static var pathToFolderContainingThisScript: URL? = {
        let cwd = FileManager.default.currentDirectoryPath

        let script = CommandLine.arguments[0]

        if script.hasPrefix("/") { // absolute
            let path = (script as NSString).deletingLastPathComponent
            return URL(fileURLWithPath: path)
        } else { // relative
            let urlCwd = URL(fileURLWithPath: cwd)

            if let urlPath = URL(string: script, relativeTo: urlCwd) {
                let path = (urlPath.path as NSString).deletingLastPathComponent
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }()

    static let emojiDirectory = URL(fileURLWithPath: "../Signal/src/util/Emoji", isDirectory: true, relativeTo: pathToFolderContainingThisScript!)

    struct EmojiData: Codable {
        let name: String?
        let unified: String
        let sortOrder: UInt
        let category: Category
        enum Category: String, Codable, CaseIterable {
            case smileys = "Smileys & Emotion"
            case people = "People & Body"
            case animals = "Animals & Nature"
            case food = "Food & Drink"
            case activities = "Activities"
            case travel = "Travel & Places"
            case objects = "Objects"
            case symbols = "Symbols"
            case flags = "Flags"
            case skinTones = "Skin Tones"
        }

        var enumName: String? {
            guard let name = name else { return nil }

            let sanitizedName = name
                .lowercased()
                .replacingOccurrences(of: " & ", with: " ")
                .replacingOccurrences(of: " - ", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "(", with: " ")
                .replacingOccurrences(of: ")", with: " ")
                .replacingOccurrences(of: "’", with: "")
                .replacingOccurrences(of: ".", with: "")

            let uppperCamelCase = sanitizedName.components(separatedBy: " ").map(titlecase).joined(separator: "")
            guard let first = uppperCamelCase.unicodeScalars.first else { return nil }
            return String(first).lowercased() + String(uppperCamelCase.unicodeScalars.dropFirst())
        }

        var emoji: String {
            let unicodeComponents = unified.components(separatedBy: "-").map { Int($0, radix: 16)! }
            return unicodeComponents.map { String(UnicodeScalar($0)!) }.joined()
        }

        func titlecase(_ value: String) -> String {
            guard let first = value.unicodeScalars.first else { return value }
            return String(first).uppercased() + String(value.unicodeScalars.dropFirst())
        }
    }

    static func generate() {
        guard let jsonData = try? Data(contentsOf: URL(string: "https://unicodey.com/emoji-data/emoji.json")!) else {
            fatalError("Failed to download emoji-data json")
        }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        let sortedEmojiData = try! jsonDecoder.decode([EmojiData].self, from: jsonData)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { $0.name != nil }

        // Main enum
        writeBlock(fileName: "Emoji.swift") { fileHandle in
            fileHandle.writeLine("/// A sorted representation of all available emoji")
            fileHandle.writeLine("enum Emoji: String, CaseIterable {")

            for emojiData in sortedEmojiData {
                guard let enumName = emojiData.enumName, let name = emojiData.name else { continue }
                fileHandle.writeLine("    case \(enumName) = \"\(name)\"")
            }

            fileHandle.writeLine("}")
        }

        // Category lookup
        writeBlock(fileName: "Emoji+Category.swift") { fileHandle in
            // Start Extension
            fileHandle.writeLine("extension Emoji {")

            // Start Category enum
            fileHandle.writeLine("    enum Category: String, CaseIterable {")
            for category in EmojiData.Category.allCases {
                fileHandle.writeLine("        case \(category) = \"\(category.rawValue)\"")
            }
            fileHandle.writeLine("")

            // Localized name for category
            fileHandle.writeLine("        var localizedName: String {")
            fileHandle.writeLine("            switch self {")

            for category in EmojiData.Category.allCases {
                fileHandle.writeLine("            case .\(category):")
                fileHandle.writeLine("                return NSLocalizedString(\"EMOJI_CATEGORY_\("\(category)".uppercased())_NAME\",")
                fileHandle.writeLine("                                         comment: \"The name for the emoji category '\(category.rawValue)'\")")
            }

            fileHandle.writeLine("            }")
            fileHandle.writeLine("        }")
            fileHandle.writeLine("")

            // Emoji lookup per category
            fileHandle.writeLine("        var emoji: [Emoji] {")
            fileHandle.writeLine("            switch self {")

            let emojiPerCategory = sortedEmojiData.reduce(into: [EmojiData.Category: [EmojiData]]()) { result, emojiData in
                var categoryList = result[emojiData.category] ?? []
                categoryList.append(emojiData)
                result[emojiData.category] = categoryList
            }

            for category in EmojiData.Category.allCases {
                guard let emoji = emojiPerCategory[category] else { continue }

                fileHandle.writeLine("            case .\(category):")

                fileHandle.writeLine("                return [")

                emoji.compactMap { $0.enumName }.forEach { name in
                    fileHandle.writeLine("                    .\(name),")
                }

                fileHandle.writeLine("                ]")
            }

            fileHandle.writeLine("            }")
            fileHandle.writeLine("        }")

            // End Category Enum
            fileHandle.writeLine("    }")

            fileHandle.writeLine("")

            // Category lookup per emoji
            fileHandle.writeLine("    var category: Category {")
            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData {
                guard let enumName = emojiData.enumName else { continue }
                fileHandle.writeLine("        case .\(enumName): return .\(emojiData.category)")
            }

            // Write a default case, because this enum is too long for the compiler to validate it's exhaustive
            fileHandle.writeLine("        default: fatalError(\"Unexpected case \\(self)\")")

            fileHandle.writeLine("        }")
            fileHandle.writeLine("    }")

            // End Extension
            fileHandle.writeLine("}")
        }

        // Value lookup
        writeBlock(fileName: "Emoji+Value.swift") { fileHandle in
            // Start Extension
            fileHandle.writeLine("extension Emoji {")

            // Value lookup per emoji
            fileHandle.writeLine("    var value: String {")
            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData {
                guard let enumName = emojiData.enumName else { continue }
                fileHandle.writeLine("        case .\(enumName): return \"\(emojiData.emoji)\"")
            }

            // Write a default case, because this enum is too long for the compiler to validate it's exhaustive
            fileHandle.writeLine("        default: fatalError(\"Unexpected case \\(self)\")")

            fileHandle.writeLine("        }")
            fileHandle.writeLine("    }")

            // End Extension
            fileHandle.writeLine("}")
        }
    }

    static func writeBlock(fileName: String, block: (FileHandle) -> Void) {
        if !FileManager.default.fileExists(atPath: emojiDirectory.path) {
            try! FileManager.default.createDirectory(at: emojiDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let url = URL(fileURLWithPath: fileName, relativeTo: emojiDirectory)

        if FileManager.default.fileExists(atPath: url.path) {
            try! FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)

        let fileHandle = try! FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }

        fileHandle.writeLine("//")
        fileHandle.writeLine("//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.")
        fileHandle.writeLine("//")

        fileHandle.writeLine("")
        fileHandle.writeLine("// This file is generated by EmojiGenerator.swift, do not manually edit it.")
        fileHandle.writeLine("")

        block(fileHandle)
    }
}

extension FileHandle {
    func writeLine(_ string: String) {
        write((string + "\n").data(using: .utf8)!)
    }
}

do {
    EmojiGenerator.generate()
}
