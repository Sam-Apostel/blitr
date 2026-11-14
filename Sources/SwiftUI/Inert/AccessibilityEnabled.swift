// iOS 18 accessibility modifiers that apply only when `isEnabled` is true, and the indefinite bounce effect.

extension View {
    public func accessibilityLabel(_ label: Text, isEnabled: Bool) -> some View {
        let s = label.plainString
        return axInfo { if isEnabled { $0.label = s } }
    }
    public func accessibilityLabel(_ labelKey: LocalizedStringKey, isEnabled: Bool) -> some View {
        let s = labelKey.plainString
        return axInfo { if isEnabled { $0.label = s } }
    }
    @_disfavoredOverload
    public func accessibilityLabel<S: StringProtocol>(_ label: S, isEnabled: Bool) -> some View {
        let s = String(label)
        return axInfo { if isEnabled { $0.label = s } }
    }
    public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> some View {
        let s = hint.plainString
        return axInfo { if isEnabled { $0.hint = s } }
    }
    public func accessibilityHint(_ hintKey: LocalizedStringKey, isEnabled: Bool) -> some View {
        let s = hintKey.plainString
        return axInfo { if isEnabled { $0.hint = s } }
    }
    @_disfavoredOverload
    public func accessibilityHint<S: StringProtocol>(_ hint: S, isEnabled: Bool) -> some View {
        let s = String(hint)
        return axInfo { if isEnabled { $0.hint = s } }
    }
    public func accessibilityValue(_ value: Text, isEnabled: Bool) -> some View {
        let s = value.plainString
        return axInfo { if isEnabled { $0.value = s } }
    }
    public func accessibilityValue(_ valueKey: LocalizedStringKey, isEnabled: Bool) -> some View {
        let s = valueKey.plainString
        return axInfo { if isEnabled { $0.value = s } }
    }
    @_disfavoredOverload
    public func accessibilityValue<S: StringProtocol>(_ value: S, isEnabled: Bool) -> some View {
        let s = String(value)
        return axInfo { if isEnabled { $0.value = s } }
    }
    public func accessibilityIdentifier(_ identifier: String, isEnabled: Bool) -> some View {
        axInfo { if isEnabled { $0.identifier = identifier } }
    }
}

/// iOS 18: bounce can repeat indefinitely (`.symbolEffect(.bounce)`, `.symbolEffect(.bounce, isActive:)`).
extension BounceSymbolEffect: IndefiniteSymbolEffect {}
