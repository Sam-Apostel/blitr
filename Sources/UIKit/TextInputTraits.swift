// UIKit's keyboard and text input traits, and the SwiftUI modifiers that take them (inert: there is no keyboard).

import SwiftUI

public enum UIKeyboardType: Int, Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad,
         emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

public struct UITextContentType: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let name = UITextContentType("name")
    public static let namePrefix = UITextContentType("namePrefix")
    public static let givenName = UITextContentType("givenName")
    public static let middleName = UITextContentType("middleName")
    public static let familyName = UITextContentType("familyName")
    public static let nameSuffix = UITextContentType("nameSuffix")
    public static let nickname = UITextContentType("nickname")
    public static let jobTitle = UITextContentType("jobTitle")
    public static let organizationName = UITextContentType("organizationName")
    public static let location = UITextContentType("location")
    public static let fullStreetAddress = UITextContentType("fullStreetAddress")
    public static let streetAddressLine1 = UITextContentType("streetAddressLine1")
    public static let streetAddressLine2 = UITextContentType("streetAddressLine2")
    public static let addressCity = UITextContentType("addressCity")
    public static let addressState = UITextContentType("addressState")
    public static let addressCityAndState = UITextContentType("addressCityAndState")
    public static let sublocality = UITextContentType("sublocality")
    public static let countryName = UITextContentType("countryName")
    public static let postalCode = UITextContentType("postalCode")
    public static let telephoneNumber = UITextContentType("telephoneNumber")
    public static let emailAddress = UITextContentType("emailAddress")
    public static let URL = UITextContentType("URL")
    public static let creditCardNumber = UITextContentType("creditCardNumber")
    public static let creditCardName = UITextContentType("creditCardName")
    public static let creditCardGivenName = UITextContentType("creditCardGivenName")
    public static let creditCardMiddleName = UITextContentType("creditCardMiddleName")
    public static let creditCardFamilyName = UITextContentType("creditCardFamilyName")
    public static let creditCardSecurityCode = UITextContentType("creditCardSecurityCode")
    public static let creditCardExpiration = UITextContentType("creditCardExpiration")
    public static let creditCardExpirationMonth = UITextContentType("creditCardExpirationMonth")
    public static let creditCardExpirationYear = UITextContentType("creditCardExpirationYear")
    public static let creditCardType = UITextContentType("creditCardType")
    public static let username = UITextContentType("username")
    public static let password = UITextContentType("password")
    public static let newPassword = UITextContentType("newPassword")
    public static let oneTimeCode = UITextContentType("oneTimeCode")
    public static let shipmentTrackingNumber = UITextContentType("shipmentTrackingNumber")
    public static let flightNumber = UITextContentType("flightNumber")
    public static let dateTime = UITextContentType("dateTime")
    public static let birthdate = UITextContentType("birthdate")
    public static let birthdateDay = UITextContentType("birthdateDay")
    public static let birthdateMonth = UITextContentType("birthdateMonth")
    public static let birthdateYear = UITextContentType("birthdateYear")
}

public enum UITextAutocapitalizationType: Int, Sendable {
    case none, words, sentences, allCharacters
}

extension View {
    public func keyboardType(_ type: UIKeyboardType) -> some View { self }
    public func textContentType(_ textContentType: UITextContentType?) -> some View { self }
    public func autocapitalization(_ style: UITextAutocapitalizationType) -> some View { self }
}
