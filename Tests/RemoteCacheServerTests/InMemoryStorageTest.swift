import NIO
import NIOFoundationCompat
@testable import RemoteCacheServer
import XCTest

class InMemoryStorageTest: XCTestCase {
  var storage: InMemoryStorage!

  override func setUp() {
    super.setUp()
    storage = InMemoryStorage()
  }

  override func tearDown() {
    super.tearDown()
    storage = nil
  }

  func testWrite() {
    let eventLoop = EmbeddedEventLoop()
    let resourceURI = "/fake/path"

    let writePromise = eventLoop.newPromise(of: CacheResponseType.self)

    let data = "my contents".data(using: .utf8)!
    storage.write(resourceURI, data: data, promise: writePromise)

    let writeExpectation = expectation(description: "write expectation")
    writePromise.futureResult.whenSuccess { _ in writeExpectation.fulfill() }

    eventLoop.run()
    waitForExpectations(timeout: 1)

    let readPromise = eventLoop.newPromise(of: CacheResponseType.self)

    storage.read(resourceURI, promise: readPromise)

    let readExpectation = expectation(description: "read expectation")
    readPromise.futureResult.whenSuccess { response in
      guard case .iodata(let cachedData) = response, case .byteBuffer(var buffer) = cachedData else {
        return
      }
      readExpectation.fulfill()
      XCTAssertEqual(data, buffer.readData(length: buffer.readableBytes))
    }
    eventLoop.run()

    waitForExpectations(timeout: 1)
  }

  func testRead() {
    let eventLoop = EmbeddedEventLoop()
    let resourceURI = "/fake/path"

    let readNotFoundPromise = eventLoop.newPromise(of: CacheResponseType.self)

    storage.read(resourceURI, promise: readNotFoundPromise)

    let readNotFoundExpectation = expectation(description: "read failure expectation")
    readNotFoundPromise.futureResult.whenSuccess { response in
      XCTAssertEqual(CacheResponseType.notFound, response)
      readNotFoundExpectation.fulfill()
    }
    eventLoop.run()
    waitForExpectations(timeout: 1)

    let data = "my contents".data(using: .utf8)!
    storage.write(resourceURI, data: data, promise: nil)

    let readSuccessPromise = eventLoop.newPromise(of: CacheResponseType.self)

    storage.read(resourceURI, promise: readSuccessPromise)

    let readSuccessExpectation = expectation(description: "read success expectation")
    readSuccessPromise.futureResult.whenSuccess { response in
      guard case .iodata(let cachedData) = response, case .byteBuffer(var buffer) = cachedData else {
        return
      }
      readSuccessExpectation.fulfill()
      XCTAssertEqual(data, buffer.readData(length: buffer.readableBytes))
    }
    eventLoop.run()
    waitForExpectations(timeout: 1)

  }
}
