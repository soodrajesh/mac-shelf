import SwiftUI

struct CalculatorView: View {
    @State private var display = "0"
    @State private var pendingValue: Double = 0
    @State private var pendingOperation: String = ""
    @State private var shouldClearDisplay = false

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    let buttons = [
        ["C", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "=", ""]
    ]

    var body: some View {
        VStack(spacing: 5) {
            Text(display)
                .appFont(.title2, weight: .light)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: 20)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(buttons, id: \.self) { row in
                    ForEach(row, id: \.self) { btn in
                        if btn.isEmpty {
                            Color.clear
                        } else {
                            Button(action: { handleTap(btn) }) {
                                Text(btn)
                                    .appFont(.callout, weight: .semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 26)
                                    .background(buttonColor(btn))
                                    .foregroundColor(.primary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: btn))
                        }
                    }
                }
            }
        }
        .frame(width: 260, height: 190)
    }

    /// Digits already read fine via `Text`; the symbol keys ("±", "÷", "−",
    /// "×", "%", "=", "C") read poorly/ambiguously on VoiceOver without an
    /// explicit label (UX-AUDIT.md finding A-3).
    func accessibilityLabel(for btn: String) -> String {
        switch btn {
        case "C": return "Clear"
        case "±": return "Toggle sign"
        case "%": return "Percent"
        case "÷": return "Divide"
        case "×": return "Multiply"
        case "−": return "Subtract"
        case "+": return "Add"
        case "=": return "Equals"
        case ".": return "Decimal point"
        default: return btn
        }
    }

    func buttonColor(_ btn: String) -> Color {
        if ["÷", "×", "−", "+", "="].contains(btn) {
            return .orange
        }
        if ["C", "±", "%"].contains(btn) {
            return Color(.systemGray)
        }
        return Color(.controlBackgroundColor)
    }

    func handleTap(_ btn: String) {
        switch btn {
        case "C":
            reset()
        case "=":
            calculate()
        case "±":
            toggleSign()
        case "%":
            applyPercent()
        case "+", "−", "×", "÷":
            handleOperation(btn)
        case ".":
            addDecimal()
        default:
            appendDigit(btn)
        }
    }

    func appendDigit(_ digit: String) {
        if shouldClearDisplay {
            display = digit
            shouldClearDisplay = false
        } else {
            if display == "0" {
                display = digit
            } else {
                display.append(digit)
            }
        }
    }

    func addDecimal() {
        if shouldClearDisplay {
            display = "0."
            shouldClearDisplay = false
        } else if !display.contains(".") {
            display.append(".")
        }
    }

    func handleOperation(_ op: String) {
        if !pendingOperation.isEmpty {
            calculate()
        }
        pendingValue = Double(display) ?? 0
        pendingOperation = op
        shouldClearDisplay = true
    }

    func calculate() {
        let currentValue = Double(display) ?? 0
        var result = currentValue

        switch pendingOperation {
        case "+":
            result = pendingValue + currentValue
        case "−":
            result = pendingValue - currentValue
        case "×":
            result = pendingValue * currentValue
        case "÷":
            // Let `formatResult`'s existing NaN/infinite check produce
            // "Error" instead of a `0` indistinguishable from a genuine
            // zero result (UX-AUDIT.md finding F-4).
            result = pendingValue / currentValue
        default:
            break
        }

        display = formatResult(result)
        pendingValue = 0
        pendingOperation = ""
        shouldClearDisplay = true
    }

    func toggleSign() {
        if let value = Double(display) {
            display = formatResult(-value)
        }
    }

    func applyPercent() {
        if let value = Double(display) {
            display = formatResult(value / 100)
        }
    }

    func formatResult(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "Error"
        }
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        let formatted = String(format: "%.2f", value)
        return formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func reset() {
        display = "0"
        pendingValue = 0
        pendingOperation = ""
        shouldClearDisplay = false
    }
}
