import Foundation
import Orion

// Sibling delegate to SPTDataLoaderService. Some regions (e.g. gae2) ship
// bootstrap / lyrics responses through this delegate instead, so both are hooked.
class HttpClientURLSessionHook: ClassHook<NSObject>, SpotifySessionDelegate {
    typealias Group = NetworkHooksGroup
    static let targetName = "Connectivity_HttpClientKit.HttpClientURLSession"

    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        captureAccessToken(from: task.currentRequest)

        guard let url = task.currentRequest?.url else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        PremiumDiag.seen(url)

        if CasitaResponseProbe.shouldProbe(url) {
            CasitaResponseProbe.flush(task, url: url)
        }

        if SpotifyResponsePatcher.shouldBlock(url) {
            orig.URLSession(session, dataTask: task, didReceiveData: SpotifyResponsePatcher.blockedResponseData(for: url))
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        guard error == nil, SpotifyResponsePatcher.shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }

        guard let buffer = URLSessionHelper.shared.obtainData(for: task) else {
            // Some Spotify builds complete "modified" tasks with 0 body bytes.
            // We previously forwarded completion only, which can crash callers that
            // assume at least one didReceiveData before completion.
            writeDebugLog("[HCUS] Missing buffered body for \(url.absoluteString) (taskId=\(task.taskIdentifier))")
            orig.URLSession(session, dataTask: task, didReceiveData: Data())
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }

        do {
            if url.isLyrics {
                let originalLyrics = try? Lyrics(serializedBytes: buffer)

                let semaphore = DispatchSemaphore(value: 0)
                var customLyricsData: Data?
                DispatchQueue.global(qos: .userInitiated).async {
                    customLyricsData = try? getLyricsDataForCurrentTrack(url.path, originalLyrics: originalLyrics)
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + .milliseconds(18000))
                orig.URLSession(session, dataTask: task, didReceiveData: customLyricsData ?? buffer)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }

            if let result = try SpotifyResponsePatcher.patch(url: url, buffer: buffer) {
                writeDebugLog("[HCUS] Patched \(result.tag.rawValue)")
                orig.URLSession(session, dataTask: task, didReceiveData: result.data)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            // patch() returned nil — no transform, but didReceiveData already
            // suppressed the original. Replay or consumer hangs.
            orig.URLSession(session, dataTask: task, didReceiveData: buffer)
            orig.URLSession(session, task: task, didCompleteWithError: nil)
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard PremiumGate.isPremium, BaseLyricsGroup.isActive,
              let url = task.currentRequest?.url, url.isLyrics, response.statusCode != 200 else {
            orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: handler)
            return
        }

        // Fetch on a background queue while holding the completion handler open.
        // Calling getLyricsDataForCurrentTrack synchronously here would block the
        // delegate queue and prevent subsequent delegate callbacks from firing.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let data = try? getLyricsDataForCurrentTrack(url.path)

            guard let lyricsData = data,
                  let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:]) else {
                handler(.allow)
                orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: { _ in })
                return
            }

            orig.URLSession(session, dataTask: task, didReceiveResponse: ok, completionHandler: handler)
            orig.URLSession(session, dataTask: task, didReceiveData: lyricsData)
            orig.URLSession(session, task: task, didCompleteWithError: nil)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard let url = task.currentRequest?.url else { return }
        if SpotifyResponsePatcher.shouldBlock(url) { return }
        if CasitaResponseProbe.shouldProbe(url) {
            CasitaResponseProbe.append(data, for: task)
        }
        if SpotifyResponsePatcher.shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: task)
            return
        }
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
