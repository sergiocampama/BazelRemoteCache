import NIO
import NIOFoundationCompat
@testable import RemoteCacheServer
import XCTest

class FilesystemStorageTest: XCTestCase {
  var storage: FilesystemStorage!
  var localURL: URL!
  var filesToClose = [FileRegion]()

  override func setUp() {
    super.setUp()

    localURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("filesystem_storage_tests")

    if FileManager.default.fileExists(atPath: localURL.path) {
      try! FileManager.default.removeItem(at: localURL)
    }
    try! FileManager.default.createDirectory(at: localURL,
                                            withIntermediateDirectories: true,
                                            attributes: nil)

    storage = FilesystemStorage(localPath: localURL.path)
  }

  override func tearDown() {
    super.tearDown()
    try! FileManager.default.removeItem(at: localURL)

    localURL = nil
    storage = nil

    for fileRegion in filesToClose {
      try! fileRegion.fileHandle.close()
    }
    filesToClose = [FileRegion]()
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
      guard case .iodata(let cachedData) = response, case .fileRegion(let fileRegion) = cachedData else {
        return
      }
      readExpectation.fulfill()
      self.filesToClose.append(fileRegion)
      XCTAssertEqual(data.count, fileRegion.readableBytes)
    }
    eventLoop.run()

    waitForExpectations(timeout: 1)
  }

  func testRead() {
    let eventLoop = EmbeddedEventLoop()
    let resourceURI = "/fake/path"

    let readNotFoundPromise = eventLoop.newPromise(of: CacheResponseType.self)

    let readNotFoundExpectation = expectation(description: "read failure expectation")
    readNotFoundPromise.futureResult.whenSuccess { response in
      XCTAssertEqual(CacheResponseType.notFound, response)
      readNotFoundExpectation.fulfill()
    }

    storage.read(resourceURI, promise: readNotFoundPromise)
    eventLoop.run()
    waitForExpectations(timeout: 1)

    let data = "my contents".data(using: .utf8)!
    let writePromise = eventLoop.newPromise(of: CacheResponseType.self)
    storage.write(resourceURI, data: data, promise: writePromise)
    eventLoop.run()
    _ = try! writePromise.futureResult.wait()

    let readSuccessPromise = eventLoop.newPromise(of: CacheResponseType.self)

    let readSuccessExpectation = expectation(description: "read success expectation")
    readSuccessPromise.futureResult.whenSuccess { response in
      guard case .iodata(let cachedData) = response, case .fileRegion(let fileRegion) = cachedData else {
        return
      }
      readSuccessExpectation.fulfill()
      self.filesToClose.append(fileRegion)
      XCTAssertEqual(data.count, fileRegion.readableBytes)
    }

    storage.read(resourceURI, promise: readSuccessPromise)
    eventLoop.run()
    waitForExpectations(timeout: 1)

  }
}
