//
//  DavRequests.swift
//  PocketInformant
//
//  Created by Stephen Kac on 1/19/21.
//  Copyright © 2021 Fanatic Software, Inc. All rights reserved.
//

import Foundation

@objc(DAVCopyRequest)
@objcMembers
class DAVCopyRequest: DAVRequest {
	var destinationPath: String?
	var overwrite = false

	func method() -> String? {
		return "COPY"
	}

	override func request() -> URLRequest? {
		assert(destinationPath != nil, "Invalid parameter not satisfying: destinationPath != nil")
		guard let destinationPath = destinationPath else {
			return nil
		}

		let newURL = concatenatedURL(with: destinationPath)

		var newReq = newRequest(with: path,
														method: method() ?? "")

		newReq.setValue(newURL.absoluteString, forHTTPHeaderField: "Destination")

		if overwrite {
			newReq.setValue("T", forHTTPHeaderField: "Overwrite")
		} else {
			newReq.setValue("F", forHTTPHeaderField: "Overwrite")
		}

		return newReq as URLRequest
	}
}

@objc(DAVDeleteRequest)
@objcMembers
class DAVDeleteRequest: DAVRequest {
	override func request() -> URLRequest? {
		return newRequest(with: path, method: "DELETE") as URLRequest
	}
}

@objc(DAVGetRequest)
@objcMembers
class DAVGetRequest: DAVRequest {
	override func request() -> URLRequest? {
		return newRequest(with: path, method: "GET") as URLRequest
	}

	func result(for data: Data?) -> Any? {
		return data
	}
}

@objc(DAVListingRequest)
@objcMembers
class DAVListingRequest: DAVRequest {
	public var depth: Int = 1

	required init(path aPath: String?) {
		super.init(path: aPath ?? "")
	}

	public required init() {
		fatalError("init() has not been implemented")
	}

	override func request() -> URLRequest? {
		var req = newRequest(with: path, method: "PROPFIND")

		if depth > 1 {
			req.setValue("infinity", forHTTPHeaderField: "Depth")
		} else {
			req.setValue(String(format: "%ld", UInt(depth)), forHTTPHeaderField: "Depth")
		}

		req.setValue("application/xml", forHTTPHeaderField: "Content-Type")

		let xml = """
            <?xml version="1.0" encoding="utf-8" ?>\n\
            <D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>
            """

		req.httpBody = xml.data(using: .utf8)

		return req as URLRequest?
	}

	override func result(for data: Data?) -> AnyObject? {
		guard let p = DAVListingParser(data: data) else {
			return nil
		}

		do {
			let items = try p.parse()
			return items as AnyObject
		}	catch {
			#if DEBUG
			print("XML Parse error: \(error)")
			#endif
			return nil
		}
	}
}

@objc(DAVMakeCollectionRequest)
@objcMembers
class DAVMakeCollectionRequest: DAVRequest {
	override func request() -> URLRequest? {
		newRequest(with: self.path, method: "MKCOL") as URLRequest?
	}
}

@objc(DAVMoveRequest)
@objcMembers
class DAVMoveRequest: DAVCopyRequest {
	override func method() -> String? {
		"MOVE"
	}
}

@objc(DAVPutRequest)
@objcMembers
class DAVPutRequest: DAVRequest {
	public var data: Data?
	public var dataMIMEType: String = "application/octet-stream"

	override func request() -> URLRequest? {

		guard let data = data else {
			assertionFailure("Invalid parameter not satisfying: pdata != nil")
			return nil
		}

		let len = String(UInt(data.count))

		var req = newRequest(with: path, method: "PUT")
		req.setValue(dataMIMEType, forHTTPHeaderField: "Content-Type")
		req.setValue(len, forHTTPHeaderField: "Content-Length")
		req.httpBody = data

		return req as URLRequest?
	}
}

extension DAVRequest {
	@objc(newRequestWithPath:method:)
	func newRequest(with path: String, method: String) -> URLRequest {
		let url = concatenatedURL(with: path)

		var request = URLRequest(url: url)
		request.httpMethod = method
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 60

		return request
	}
}
