import Foundation
import JavaScriptCore

private func objectToDictionary<T>(_ object: T) -> [String: Any] {
    let mirror = Mirror(reflecting: object)
    var dictionary: [String: Any] = [:]

    for case let (label?, value) in mirror.children {
        dictionary[label] = unwrap(value)
    }

    return dictionary
}

/// Helper function to unwrap any potential Optional value.
/// It recursively unwraps optionals to ensure the actual value is extracted,
/// and handles conversion of nested objects and collections to dictionaries.
private func unwrap(_ any: Any) -> Any {
    let mirror = Mirror(reflecting: any)
    if mirror.displayStyle != .optional {
        return convertValue(any)
    }

    if mirror.children.isEmpty { return NSNull() }
    // swiftlint:disable:next force_unwrapping
    let (_, some) = mirror.children.first!
    return unwrap(some)
}

/// Convert value to a compatible format, handling specific types like arrays and nested objects.
private func convertValue(_ value: Any) -> Any {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .collection:
        // swiftlint:disable:next force_cast
        return (value as! [Any]).map { unwrap($0) }
    case .dictionary:
        var dict: [AnyHashable: Any] = [:]
        // swiftlint:disable:next all
        for case let (key, v) in value as! [AnyHashable: Any] {
            dict[key] = unwrap(v)
        }
        return dict
    case .struct, .class:
        return objectToDictionary(value)
    default:
        return value
    }
}

// Serializes a struct or class to JSValue object.
func serializeToJSValue(_ object: Any?, _ context: JSContext) throws -> JSValue {
    if let object = object {
        let dictionary = objectToDictionary(object)
        return JSValue(object: dictionary, in: context)
    }
    return JSValue(nullIn: context)
}
