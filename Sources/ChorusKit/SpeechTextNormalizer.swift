import Foundation

/// English spoken forms for inference only. Editor text and saved scripts stay verbatim.
public enum SpeechTextNormalizer {
    public static func normalize(_ text: String) -> String {
        // Do not reinterpret model tags, web addresses, identifiers, versions or dates.
        let opaque = #"\[[^\]\r\n]*\]|(?:https?://|www\.)[^\s\[\]]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\b(?:v)?\d+(?:\.\d+){2,}\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b|\b(?=[A-Za-z0-9_]*[A-Za-z_])(?=[A-Za-z0-9_]*\d)[A-Za-z0-9_]+\b|\b[A-Za-z0-9_-]+\.(?:txt|wav|mp3|json|swift|pdf)\b"#
        let source = text as NSString
        var result = "", cursor = 0
        for match in regex(opaque, options: .caseInsensitive).matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += prose(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        result += prose(source.substring(from: cursor))
        return result
    }

    private static let initialisms = ["AI", "API", "CPU", "GPU", "TTS", "WAV", "URL", "USB", "UK", "USA", "US", "EU", "OSS", "ML", "MIT", "MRI", "SMS", "FAQ", "HTTP", "HTTPS"]
    private static let wordAcronyms = ["NASA", "NATO", "UNESCO"]
    private static let digits = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    private static let number = #"(?:\d{1,3}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+|\d+)"#

    private static func prose(_ source: String) -> String {
        var text = normalizeCapitals(source)
        // Consume the dots in a.m./p.m. so the engine does not split the clock time.
        text = replacing(text, #"(?i)(?<![\w.:])([0-9]{1,2}):([0-9]{2})\s*([ap])\.?m\.?(?!\w)"#) { match, ns in
            guard let hour = Int(ns.substring(with: match.range(at: 1))), (1...12).contains(hour),
                  let minute = Int(ns.substring(with: match.range(at: 2))), (0...59).contains(minute) else { return nil }
            let meridiem = ns.substring(with: match.range(at: 3)).lowercased()
            let period: String
            if meridiem == "a" { period = hour == 12 ? "at night" : "in the morning" }
            else { period = hour == 12 || hour < 6 ? "in the afternoon" : hour < 9 ? "in the evening" : "at night" }
            let original = ns.substring(with: match.range)
            let following = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
            // In "a.m. Bring ...", the last dot also ends a sentence. Keep that pause.
            let sentenceEnd = original.hasSuffix(".") && following.first?.isUppercase == true ? "." : ""
            return clock(hour, minute) + " " + period + sentenceEnd
        }
        // A bare H:MM is read literally; no morning/afternoon is inferred.
        text = replacing(text, #"(?i)(?<![\w.:])([0-9]{1,2}):([0-9]{2})(?![\w:]|\s*[ap]\.?m)"#) { match, ns in
            guard let hour = Int(ns.substring(with: match.range(at: 1))), (0...23).contains(hour),
                  let minute = Int(ns.substring(with: match.range(at: 2))), (0...59).contains(minute) else { return nil }
            return minute == 0 ? integer(String(hour))! + " o'clock" : clock(hour, minute)
        }
        text = replacing(text, #"(?<!\w)([₹$£€])\s*([-+]?"# + number + #"(?:\.\d{1,2})?)(?!\w|[.,:/]\d)"#) { match, ns in
            let symbol = ns.substring(with: match.range(at: 1))
            var amount = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")
            let sign = amount.hasPrefix("-") ? "minus " : amount.hasPrefix("+") ? "plus " : ""
            if amount.hasPrefix("-") || amount.hasPrefix("+") { amount.removeFirst() }
            let parts = amount.components(separatedBy: ".")
            guard let whole = integer(parts[0]) else { return nil }
            let units: (String, String, String, String)
            switch symbol {
            case "₹": units = ("rupee", "rupees", "paisa", "paise")
            case "£": units = ("pound", "pounds", "penny", "pence")
            case "€": units = ("euro", "euros", "cent", "cents")
            default: units = ("dollar", "dollars", "cent", "cents")
            }
            var spoken = sign + whole + " " + (Int64(parts[0]) == 1 ? units.0 : units.1)
            if parts.count == 2, let fraction = Int(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0)), fraction > 0 {
                spoken += " and " + integer(String(fraction))! + " " + (fraction == 1 ? units.2 : units.3)
            }
            return spoken
        }
        text = replacing(text, #"(?<![\w.:/])([-+]?"# + number + #")\.([0-9]+)(?!\w|[.:/]\d)"#) { match, ns in
            guard let whole = signedInteger(ns.substring(with: match.range(at: 1))) else { return nil }
            return whole + " point " + ns.substring(with: match.range(at: 2)).map { digits[Int(String($0))!] }.joined(separator: " ")
        }
        text = replacing(text, #"(?<![\w.:/])[-+]?"# + number + #"(?!\w|[.:/]\d|,\d)"#) { match, ns in
            signedInteger(ns.substring(with: match.range))
        }
        let abbreviations = ["dr": "doctor", "mr": "mister", "mrs": "missus", "ms": "miz", "prof": "professor", "jr": "junior", "sr": "senior", "vs": "versus", "approx": "approximately", "etc": "et cetera", "e.g": "for example", "i.e": "that is"]
        text = replacing(text, #"(?i)\b(dr|mr|mrs|ms|prof|jr|sr|vs|approx|etc|e\.g|i\.e)\.(?=\s|$)"#) { match, ns in
            let original = ns.substring(with: match.range(at: 1))
            guard let expanded = abbreviations[original.lowercased()] else { return nil }
            return original.first?.isUppercase == true ? capitalizedFirst(expanded) : expanded
        }
        // Only a known list is spelled out. Lowercase 'us', 'am', etc. remain ordinary words.
        text = replacing(text, #"\b(?:"# + initialisms.joined(separator: "|") + #")\b"#) { match, ns in
            ns.substring(with: match.range).map(String.init).joined(separator: " ")
        }
        text = replacing(text, #"(?<!\w)(?:[A-Z]\.){2,}(?!\w)"#) { match, ns in
            ns.substring(with: match.range).filter { $0 != "." }.map(String.init).joined(separator: " ")
        }
        return text
    }

    private static func normalizeCapitals(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        let allCaps = !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        let keep = Set(initialisms + wordAcronyms + ["I"])
        return replacing(text, #"\b[A-Z]+(?:[ \t]+[A-Z]+)*\b"#) { match, ns in
            let run = ns.substring(with: match.range)
            guard allCaps || run.split(whereSeparator: \.isWhitespace).count > 1 else { return nil }
            var words = replacing(run, #"\b[A-Z]+\b"#) { word, original in
                let token = original.substring(with: word.range)
                return token.count == 1 || keep.contains(token) ? token : token.lowercased()
            }
            let before = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
            if before.isEmpty || before.last.map({ ".!?\n".contains($0) }) == true { words = capitalizedFirst(words) }
            return words
        }
    }

    private static func clock(_ hour: Int, _ minute: Int) -> String {
        integer(String(hour))! + (minute == 0 ? "" : minute < 10 ? " oh " + integer(String(minute))! : " " + integer(String(minute))!)
    }
    private static func signedInteger(_ input: String) -> String? {
        var value = input.replacingOccurrences(of: ",", with: "")
        let sign = value.hasPrefix("-") ? "minus " : value.hasPrefix("+") ? "plus " : ""
        if value.hasPrefix("-") || value.hasPrefix("+") { value.removeFirst() }
        return integer(value).map { sign + $0 }
    }
    private static func integer(_ input: String) -> String? {
        guard input.count <= 15, let value = Int64(input) else { return nil }
        // Explicit locale: the user's macOS region must not change the spoken language.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: value))
    }
    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }
    private static func replacing(_ text: String, _ pattern: String,
                                  transform: (NSTextCheckingResult, NSString) -> String?) -> String {
        let source = text as NSString
        var result = text
        for match in regex(pattern).matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            if let replacement = transform(match, source), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
}
