import Foundation

struct CalculatorSearchService {
    func search(query: String) -> [SearchResult] {
        guard let calculation = Calculator.evaluate(query) else { return [] }

        return [
            SearchResult(
                title: calculation.result,
                subtitle: "\(calculation.expression) = \(calculation.result)",
                detail: "Press Return to copy result",
                visual: .symbol("function"),
                action: .copyText(calculation.result)
            )
        ]
    }
}

private enum Calculator {
    struct Calculation {
        let expression: String
        let result: String
    }

    static func evaluate(_ input: String) -> Calculation? {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeExpression(expression) else { return nil }

        var parser = CalculatorParser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }

        return Calculation(expression: expression, result: format(value))
    }

    private static func looksLikeExpression(_ expression: String) -> Bool {
        guard expression.isEmpty == false else { return false }
        guard expression.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil else { return false }
        guard expression.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/÷×xX%^")) != nil else { return false }

        let allowedCharacters = CharacterSet(charactersIn: "0123456789.+-*/÷×xX%^() ")
        return expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 12
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct CalculatorParser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        characters = Array(expression)
    }

    mutating func parse() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipSpaces()
        return index == characters.count ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }

        while true {
            skipSpaces()
            if consume("+") {
                guard let rhs = parseTerm() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = parseTerm() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parsePower() else { return nil }

        while true {
            skipSpaces()
            if consume("*") || consume("×") || consume("x") || consume("X") {
                guard let rhs = parsePower() else { return nil }
                value *= rhs
            } else if consume("/") || consume("÷") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value /= rhs
            } else if consume("%") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value.formTruncatingRemainder(dividingBy: rhs)
            } else {
                return value
            }
        }
    }

    private mutating func parsePower() -> Double? {
        guard let base = parseFactor() else { return nil }
        skipSpaces()
        guard consume("^") else { return base }
        guard let exponent = parsePower() else { return nil }
        return pow(base, exponent)
    }

    private mutating func parseFactor() -> Double? {
        skipSpaces()

        if consume("+") {
            return parseFactor()
        }
        if consume("-") {
            guard let value = parseFactor() else { return nil }
            return -value
        }
        if consume("(") {
            guard let value = parseExpression() else { return nil }
            skipSpaces()
            guard consume(")") else { return nil }
            return value
        }

        return parseNumber()
    }

    private mutating func parseNumber() -> Double? {
        skipSpaces()
        let start = index
        var didReadDecimalPoint = false

        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                index += 1
            } else if character == ".", didReadDecimalPoint == false {
                didReadDecimalPoint = true
                index += 1
            } else {
                break
            }
        }

        guard start != index else { return nil }
        return Double(String(characters[start..<index]))
    }

    private mutating func skipSpaces() {
        while index < characters.count && characters[index].isWhitespace {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard index < characters.count, characters[index] == character else { return false }
        index += 1
        return true
    }
}
