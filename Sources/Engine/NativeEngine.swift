//
//  NativeEngine.swift
//  Starscream
//
//  Created by Dalton Cherry on 6/15/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public class NativeEngine: NSObject, Engine, URLSessionDataDelegate, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    weak var delegate: EngineDelegate?
    
    deinit {
        stop(closeCode: CloseCode.normal.rawValue)
    }

    public func register(delegate: EngineDelegate) {
        self.delegate = delegate
    }

    public func start(request: URLRequest) {
        let sessionDelegate = WebSocketDelegateProxy(handler: self)
        session = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
        task = session?.webSocketTask(with: request)
        doRead()
        task?.resume()
    }

    public func stop(closeCode: UInt16) {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: Int(closeCode)) ?? .normalClosure
        task?.cancel(with: closeCode, reason: nil)
        session?.invalidateAndCancel()
    }

    public func forceStop() {
        stop(closeCode: UInt16(URLSessionWebSocketTask.CloseCode.abnormalClosure.rawValue))
    }

    public func write(string: String, completion: (() -> ())?) {
        task?.send(.string(string), completionHandler: { (error) in
            completion?()
        })
    }

    public func write(data: Data, opcode: FrameOpCode, completion: (() -> ())?) {
        switch opcode {
        case .binaryFrame:
            task?.send(.data(data), completionHandler: { (error) in
                completion?()
            })
        case .textFrame:
            let text = String(data: data, encoding: .utf8)!
            write(string: text, completion: completion)
        case .ping:
            task?.sendPing(pongReceiveHandler: { (error) in
                completion?()
            })
        default:
            break //unsupported
        }
    }

    private func doRead() {
        task?.receive { [weak self] (result) in
            switch result {
            case .success(let message):
                switch message {
                case .string(let string):
                    self?.broadcast(event: .text(string))
                case .data(let data):
                    self?.broadcast(event: .binary(data))
                @unknown default:
                    break
                }
                
                self?.doRead()
                
            case .failure(let error):
                self?.broadcast(event: .error(error))
            }
        }
    }

    private func broadcast(event: WebSocketEvent) {
        delegate?.didReceive(event: event)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let p = `protocol` ?? ""
        broadcast(event: .connected([HTTPWSHeader.protocolName: p]))
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var r = ""
        if let d = reason {
            r = String(data: d, encoding: .utf8) ?? ""
        }
        broadcast(event: .disconnected(r, UInt16(closeCode.rawValue)))
    }
}

/// URLSession holds onto its delegate with a strong reference, so this class
/// acts as an intermediate handler. The URLSession will hold a strong reference to it,
/// and this will hold a weak reference to the true delegate, allowing us to gracefully
/// deinitialize within NativeEngine.
///
///     NativeEngine ------> URLSession ------> DelegateProxy
///         ^        strong             strong        |
///         |                                         |
///          ----------------- weak ------------------
///
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
class WebSocketDelegateProxy: NSObject, URLSessionWebSocketDelegate {
    
    weak var delegate: URLSessionWebSocketDelegate?
    
    init(handler: URLSessionWebSocketDelegate?) {
        self.delegate = handler
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        delegate?.urlSession?(session, webSocketTask: webSocketTask, didOpenWithProtocol: `protocol`)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        delegate?.urlSession?(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
    }
    
}
