// MeasurementFormatter, which swift-corelibs-foundation declares unavailable. English names; the default
// options convert to the locale's measurement system (US: miles, °F, pounds, mph), as on Apple platforms.
// Apple's Foundation has the real one, so on Darwin this compiles out.
import Foundation

#if !canImport(Darwin)

open class MeasurementFormatter: Formatter, @unchecked Sendable {
    public struct UnitOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let providedUnit = UnitOptions(rawValue: 1 << 0)
        public static let naturalScale = UnitOptions(rawValue: 1 << 1)
        public static let temperatureWithoutUnit = UnitOptions(rawValue: 1 << 2)
    }

    open var unitOptions: UnitOptions = []
    open var unitStyle: Formatter.UnitStyle = .medium
    open var locale: Locale! = .current
    open var numberFormatter: NumberFormatter! = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 3
        return f
    }()

    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open func string<UnitType: Unit>(from measurement: Measurement<UnitType>) -> String {
        var value = measurement.value
        var unit: Unit = measurement.unit
        if let dimension = unit as? Dimension, !unitOptions.contains(.providedUnit) {
            let target = preferredUnit(for: dimension, value: value)
            if target !== dimension {
                value = target.converter.value(fromBaseUnitValue: dimension.converter.baseUnitValue(fromValue: value))
                unit = target
            }
        }
        if unitOptions.contains(.naturalScale), let dimension = unit as? Dimension {
            (value, unit) = naturalScale(value, dimension)
        }
        let formatter = numberFormatter ?? NumberFormatter()
        if formatter.locale != locale { formatter.locale = locale }
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        if unit is UnitTemperature && unitOptions.contains(.temperatureWithoutUnit) { return number + "°" }
        switch unitStyle {
        case .short:
            if unit is UnitTemperature { return number + "°" }
            return number + Self.symbol(unit)
        case .long:
            return number + " " + Self.name(unit, plural: value != 1)
        default:
            let symbol = Self.symbol(unit)
            return symbol.hasPrefix("°") || symbol == "%" ? number + symbol : number + " " + symbol
        }
    }

    open func string(from unit: Unit) -> String {
        unitStyle == .long ? Self.name(unit, plural: true) : Self.symbol(unit)
    }

    open override func string(for obj: Any?) -> String? {
        if let m = obj as? Measurement<Unit> { return string(from: m) }
        if let m = obj as? Measurement<Dimension> { return string(from: m) }
        return nil
    }

    // MARK: Units

    private var usesUSUnits: Bool {
        let region = (locale ?? .current).identifier.split(separator: "_").last.map(String.init) ?? "US"
        return ["US", "LR", "MM"].contains(region) || (locale ?? .current).identifier == "en"
    }

    private func preferredUnit(for unit: Dimension, value: Double) -> Dimension {
        let us = usesUSUnits
        switch unit {
        case let u as UnitTemperature: return us ? UnitTemperature.fahrenheit : (u.symbol == "°C" ? u : UnitTemperature.celsius)
        case let u as UnitLength:
            let metric = ["m", "km", "cm", "mm"], imperial = ["mi", "ft", "in", "yd"]
            if us, metric.contains(u.symbol) { return u.symbol == "km" ? UnitLength.miles : (u.symbol == "m" ? UnitLength.feet : UnitLength.inches) }
            if !us, imperial.contains(u.symbol) { return u.symbol == "mi" ? UnitLength.kilometers : (u.symbol == "in" ? UnitLength.centimeters : UnitLength.meters) }
            return u
        case let u as UnitMass:
            if us, u.symbol == "kg" || u.symbol == "g" { return u.symbol == "kg" ? UnitMass.pounds : UnitMass.ounces }
            if !us, u.symbol == "lb" || u.symbol == "oz" { return u.symbol == "lb" ? UnitMass.kilograms : UnitMass.grams }
            return u
        case let u as UnitSpeed:
            if us, u.symbol == "km/h" || u.symbol == "m/s" { return UnitSpeed.milesPerHour }
            if !us, u.symbol == "mph" { return UnitSpeed.kilometersPerHour }
            return u
        default: return unit
        }
    }

    private func naturalScale(_ value: Double, _ unit: Dimension) -> (Double, Unit) {
        func convert(_ to: Dimension) -> (Double, Unit) {
            (to.converter.value(fromBaseUnitValue: unit.converter.baseUnitValue(fromValue: value)), to)
        }
        let base = unit.converter.baseUnitValue(fromValue: abs(value))
        switch unit {
        case is UnitLength:
            if ["mi", "ft", "in", "yd"].contains(unit.symbol) { return base >= 1609.344 * 0.1 ? convert(UnitLength.miles) : convert(UnitLength.feet) }
            return base >= 1000 ? convert(UnitLength.kilometers) : base >= 1 ? convert(UnitLength.meters) : convert(UnitLength.centimeters)
        case is UnitMass:
            if unit.symbol == "lb" || unit.symbol == "oz" { return base >= 0.45359237 ? convert(UnitMass.pounds) : convert(UnitMass.ounces) }
            return base >= 1 ? convert(UnitMass.kilograms) : convert(UnitMass.grams)
        case is UnitDuration:
            return base >= 3600 ? convert(UnitDuration.hours) : base >= 60 ? convert(UnitDuration.minutes) : convert(UnitDuration.seconds)
        case is UnitInformationStorage:
            return base >= 8e9 ? convert(UnitInformationStorage.gigabytes) : base >= 8e6 ? convert(UnitInformationStorage.megabytes)
                : base >= 8e3 ? convert(UnitInformationStorage.kilobytes) : convert(UnitInformationStorage.bytes)
        default: return (value, unit)
        }
    }

    static func symbol(_ unit: Unit) -> String {
        if unit is UnitDuration {
            switch unit.symbol {
            case "hr", "h": return "hr"
            case "min": return "min"
            case "s", "sec": return "sec"
            default: break
            }
        }
        return unit.symbol
    }

    private static let names: [String: (String, String)] = [
        "m": ("meter", "meters"), "km": ("kilometer", "kilometers"), "cm": ("centimeter", "centimeters"), "mm": ("millimeter", "millimeters"),
        "mi": ("mile", "miles"), "ft": ("foot", "feet"), "in": ("inch", "inches"), "yd": ("yard", "yards"),
        "kg": ("kilogram", "kilograms"), "g": ("gram", "grams"), "lb": ("pound", "pounds"), "oz": ("ounce", "ounces"), "st": ("stone", "stones"),
        "°C": ("degree Celsius", "degrees Celsius"), "°F": ("degree Fahrenheit", "degrees Fahrenheit"), "K": ("kelvin", "kelvins"),
        "hr": ("hour", "hours"), "min": ("minute", "minutes"), "sec": ("second", "seconds"), "ms": ("millisecond", "milliseconds"),
        "km/h": ("kilometer per hour", "kilometers per hour"), "mph": ("mile per hour", "miles per hour"), "m/s": ("meter per second", "meters per second"),
        "L": ("liter", "liters"), "mL": ("milliliter", "milliliters"), "gal": ("gallon", "gallons"), "fl oz": ("fluid ounce", "fluid ounces"),
        "cup": ("cup", "cups"), "kcal": ("kilocalorie", "kilocalories"), "cal": ("calorie", "calories"), "kJ": ("kilojoule", "kilojoules"),
        "kWh": ("kilowatt-hour", "kilowatt-hours"), "W": ("watt", "watts"), "kW": ("kilowatt", "kilowatts"),
        "B": ("byte", "bytes"), "kB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"), "GB": ("gigabyte", "gigabytes"),
        "%": ("percent", "percent"), "hPa": ("hectopascal", "hectopascals"), "°": ("degree", "degrees"),
    ]

    static func name(_ unit: Unit, plural: Bool) -> String {
        let symbol = Self.symbol(unit)
        guard let pair = names[symbol] else { return symbol }
        return plural ? pair.1 : pair.0
    }
}
#endif
