//
//  DavRequest+URLSessionTaskDelegate.swift
//  Universal
//
//  Created by Stephen Kac on 1/19/21.
//  Copyright © 2021 Fanatic Software, Inc. All rights reserved.
//

import Foundation

@objc(DAVRequestDelegate)
protocol DAVRequestDelegate {
	@objc(request:didFailWithError:)
	func requestFailed(request: DAVRequest, with: Error)

	@objc(request:didSucceedWithResult:)
	func requestSucceeded(request: DAVRequest, with result: AnyObject?)

	@objc(requestDidBegin:)
	optional func requestDidBegin(request: DAVRequest)
}

@objc(DAVRequest)
@objcMembers
open class DAVRequest: DAVBaseRequest {

	private enum Constant {
		static let timeout = 60
		static let errorDomain = "com.MattRajca.DAVKit.error"
	}

	var delegate: DAVRequestDelegate?

	var path: String = ""

	private var connection: URLSessionTask?
	private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
	private var data: Data?
	private var canceled = false
	private var done = false

	internal var executingRequest = false

	open override var isAsynchronous: Bool {
		true
	}

	open override var isConcurrent: Bool {
		isAsynchronous
	}

	open override var isFinished: Bool {
		done
	}

	open override var isCancelled: Bool {
		canceled
	}

	open override var isExecuting: Bool {
		executingRequest
	}

	open override func cancel() {
		cancel(with: -1)
	}

	@objc(cancelWithCode:)
	func cancel(with code: Int) {
		willChangeValue(for: \.isCancelled)

		connection?.cancel()
		canceled = true

		didFail(NSError(domain: Constant.errorDomain,
										code: code,
										userInfo: nil))
	}

	@objc(initWithPath:)
	public required init(path: String?) {
		super.init()

		self.path = path ?? ""
	}

	open override func start() {
		guard Thread.isMainThread else {
			OperationQueue.main.addOperation {
				self.start()
			}
			return
		}

		willChangeValue(for: \.isExecuting)

		executingRequest = true

		connection = session.dataTask(with: self.request()!)

		delegate?.requestDidBegin?(request: self)

		didChangeValue(for: \.isExecuting)
	}

	func didFinish() {
		willChangeValue(for: \.isExecuting)
		willChangeValue(for: \.isFinished)

		done = true
		executingRequest = false

		didChangeValue(for: \.isExecuting)
		didChangeValue(for: \.isFinished)
	}

	func didFail(_ error: Error) {
		delegate?.requestFailed(request: self, with: error)
	}

	/* must be overriden by subclasses */
	func request() -> URLRequest? {
		assertionFailure("Subclasses of DAVRequest must override 'request'")
		return nil
	}

	@objc(resultForData:)
	func result(for data: Data?) -> AnyObject? {
		return nil
	}

	@objc(concatenatedURLWithPath:)
	func concatenatedURL(with path: String) -> URL {
		rootURL.appendingPathComponent(path)
	}

}

extension DAVRequest: URLSessionDataDelegate {

	@objc
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		defer {
			didFinish()
		}

		if let error = error {
			didFail(error)
			return
		}

		let result = self.result(for: self.data as Data?)
		delegate?.requestSucceeded(request: self, with: result)
	}

	@objc
	public func urlSession(_ session: URLSession,
												 didReceive challenge: URLAuthenticationChallenge,
												 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		do {
			let protectionSpace = challenge.protectionSpace.authenticationMethod

			guard protectionSpace == NSURLAuthenticationMethodDefault ||
							protectionSpace == NSURLAuthenticationMethodHTTPBasic ||
							protectionSpace == NSURLAuthenticationMethodHTTPDigest ||
							protectionSpace == NSURLAuthenticationMethodServerTrust
			else {
				completionHandler(.rejectProtectionSpace, nil)
				return
			}
		}

		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			if self.allowUntrustedCertificate,
				 let serverTrust = challenge.protectionSpace.serverTrust {
				let credential = URLCredential(trust: serverTrust)
				completionHandler(.useCredential, credential)
			}

			challenge.sender?.continueWithoutCredential(for: challenge)
		} else {
			if challenge.previousFailureCount == 0 {
				let credential = URLCredential(user: credentials.username,
																			 password: credentials.password,
																			 persistence: .none)

				completionHandler(.useCredential, credential)
			} else {
				// Wrong login/password
				completionHandler(.cancelAuthenticationChallenge, nil)
			}
		}
		
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		if let httpResponse = response as? HTTPURLResponse {
			guard httpResponse.statusCode < 400 else {
				cancel(with: httpResponse.statusCode)
				completionHandler(.cancel)
				return
			}
		}

		completionHandler(.allow)
	}

	@objc
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		if self.data != nil {
			self.data?.append(data)
		} else {
			self.data = NSMutableData(data: data) as Data
		}
	}

}
