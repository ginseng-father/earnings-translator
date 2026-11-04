import Foundation
@testable import TranslatorCore

func q(_ value: String, _ unit: QuantityUnit = .plain) -> Quantity {
    Quantity(Decimal(string: value)!, unit)
}
