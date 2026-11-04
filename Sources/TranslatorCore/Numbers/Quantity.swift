import Foundation

public enum QuantityUnit: Sendable, Hashable {
    case plain, percent, percentagePoints, basisPoints, quarter, fiscalYear
}

/// A number said in a sentence, normalized so English and Korean renderings
/// of the same figure compare equal: currency symbols dropped, scale words
/// (billion, 억, …) multiplied out, two-digit fiscal years expanded to 20xx.
public struct Quantity: Sendable, Hashable, CustomStringConvertible {
    public let value: Decimal
    public let unit: QuantityUnit

    public init(_ value: Decimal, _ unit: QuantityUnit) {
        self.value = value
        self.unit = unit
    }

    public var description: String {
        let number = NSDecimalNumber(decimal: value).stringValue
        switch unit {
        case .plain: return number
        case .percent: return "\(number)%"
        case .percentagePoints: return "\(number)%p"
        case .basisPoints: return "\(number)bp"
        case .quarter: return "Q\(number)"
        case .fiscalYear: return "FY\(number)"
        }
    }
}

extension Decimal {
    /// Parses "1,250.5" style digits without going through Double.
    init?(digits: String) {
        self.init(string: digits.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }
}
