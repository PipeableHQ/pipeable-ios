import JavaScriptCore
@testable import PipeableSDK
import XCTest

// swiftlint:disable force_cast

final class ScriptSerializerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var context: JSContext!

    override func setUp() {
        super.setUp()

        self.context = JSContext()
    }

    func testSerializeASimpleStruct() throws {
        struct SimpleStruct {
            public var int: Int
            public var string: String
        }

        let value = SimpleStruct(int: 42, string: "test")
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isObject)

        let dict = jsValue.toDictionary()
        XCTAssertEqual(dict?["int"] as! Int, 42)
        XCTAssertEqual(dict?["string"] as! String, "test")
    }

    func testSerializeASimpleClass() throws {
        class SimpleClass {
            public var int = 42
            public var string = "test"
        }

        let value = SimpleClass()
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isObject)

        let dict = jsValue.toDictionary()
        XCTAssertEqual(dict?["int"] as! Int, 42)
        XCTAssertEqual(dict?["string"] as! String, "test")
    }

    func testSerializeAnArray() throws {
        let value = [1, 2, 3]
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isArray)

        let array = jsValue.toArray()
        XCTAssertEqual(array?[0] as! Int, 1)
        XCTAssertEqual(array?[1] as! Int, 2)
        XCTAssertEqual(array?[2] as! Int, 3)
    }

    func testSerializeInt() throws {
        let value = 5
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isNumber)

        let number = jsValue.toNumber()
        XCTAssertEqual(number, 5)
    }

    func testSerializeString() throws {
        let value = "test"
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isString)

        let number = jsValue.toString()
        XCTAssertEqual(number, "test")
    }

    func testSerializeAClassWithComplexProperties() throws {
        class SimpleStruct {
            public var string = "test"
        }
        class SimpleClass {
            public var int = 6
        }
        class ComplexClass {
            public var int = 42
            public var string: String?
            public var array = [1, 2]
            public var dict = ["test": 1]
            public var simpleStruct = SimpleStruct()
            public var simpleClass = SimpleClass()
        }

        let value = ComplexClass()
        let jsValue = try serializeToJSValue(value, self.context)

        XCTAssertTrue(jsValue.isObject)

        let complexClass = jsValue.toDictionary()
        XCTAssertEqual(complexClass?["int"] as! Int, 42)
        XCTAssertEqual(complexClass?["string"] as! NSNull, NSNull())

        let array = complexClass?["array"] as! [Int]
        XCTAssertEqual(array[0], 1)
        XCTAssertEqual(array[1], 2)

        let dict = complexClass?["dict"] as! [String: Any]
        XCTAssertEqual(dict["test"] as! Int, 1)

        let simpleStruct = complexClass?["simpleStruct"] as! [String: Any]
        XCTAssertEqual(simpleStruct["string"] as! String, "test")

        let simpleClass = complexClass?["simpleClass"] as! [String: Any]
        XCTAssertEqual(simpleClass["int"] as! Int, 6)
    }
}
