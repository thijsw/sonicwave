import Foundation

/// Streams an HTTP body as it arrives, delivering `Data` chunks via an
/// `AsyncThrowingStream`. Used by the progressive decode pipeline so audio
/// starts before the whole file is downloaded. See docs/03-playback-engine.md.
final class DataStreamLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var session: URLSession?

    /// Begin streaming `url`. The returned stream finishes when the transfer
    /// completes (or throws on error). Cancelling/terminating the stream
    /// cancels the underlying request.
    func stream(from url: URL) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: url)
            continuation.onTermination = { _ in
                task.cancel()
                session.finishTasksAndInvalidate()
            }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation?.finish(throwing: SubsonicError.http(status: http.statusCode))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as? URLError)?.code != .cancelled {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}
