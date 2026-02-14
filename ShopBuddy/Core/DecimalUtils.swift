import Foundation

func parseDecimal(_ text: String) -> Decimal? {
    let trimmed = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: " ", with: "")

    guard !trimmed.isEmpty else { return nil }

    if let parsed = Decimal(string: trimmed, locale: Locale.current) {
        return parsed
    }

    if let parsed = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) {
        return parsed
    }

    let normalized = normalizeDecimalSeparators(in: trimmed)
    return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
}

func parseDecimalOrZero(_ text: String) -> Decimal {
    parseDecimal(text) ?? 0
}

func formatDecimalForUI(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2

    if let formatted = formatter.string(from: NSDecimalNumber(decimal: value)) {
        return formatted
    }

    return NSDecimalNumber(decimal: value).stringValue
}

private func normalizeDecimalSeparators(in text: String) -> String {
    var candidate = text

    let lastComma = candidate.lastIndex(of: ",")
    let lastDot = candidate.lastIndex(of: ".")

    if let comma = lastComma, let dot = lastDot {
        if comma > dot {
            candidate = candidate.replacingOccurrences(of: ".", with: "")
            candidate = candidate.replacingOccurrences(of: ",", with: ".")
        } else {
            candidate = candidate.replacingOccurrences(of: ",", with: "")
        }
        return candidate
    }

    if candidate.filter({ $0 == "," }).count > 1 {
        candidate = replaceAllButLast(character: ",", with: ".", in: candidate)
        return candidate
    }

    if candidate.filter({ $0 == "." }).count > 1 {
        candidate = replaceAllButLast(character: ".", with: ".", in: candidate)
        return candidate
    }

    if candidate.contains(",") {
        candidate = candidate.replacingOccurrences(of: ",", with: ".")
    }

    return candidate
}

private func replaceAllButLast(character: Character, with replacement: Character, in text: String) -> String {
    let chars = Array(text)
    guard let lastIndex = chars.lastIndex(of: character) else { return text }

    var output: [Character] = []
    output.reserveCapacity(chars.count)

    for (index, char) in chars.enumerated() {
        if char == character {
            if index == lastIndex {
                output.append(replacement)
            }
            continue
        }
        output.append(char)
    }

    return String(output)
}
