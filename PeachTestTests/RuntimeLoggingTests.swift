import Foundation
import XCTest
@testable import PeachTestCore

final class RuntimeLoggingTests: XCTestCase {
    private actor CaptureTransport {
        var sentBatches: [PeachLogUploadBatch] = []
        var failNext = false
        var responseFileBytes: Int64 = 0

        func setFail(_ value: Bool) { failNext = value }
        func setResponseBytes(_ bytes: Int64) { responseFileBytes = bytes }

        func handle(_ batch: PeachLogUploadBatch) throws -> PeachLogUploadResponse {
            if failNext {
                throw URLError(.notConnectedToInternet)
            }
            sentBatches.append(batch)
            return PeachLogUploadResponse(
                ok: true,
                accepted: batch.entries.count,
                deduplicated: 0,
                expiredDropped: 0,
                invalidDropped: 0,
                prunedExisting: 0,
                fileBytes: responseFileBytes,
                serverTime: 1_750_000_500
            )
        }
    }

    func testRedactorMasksCredentialsCookiesTokensAndSignedURLsWhileKeepingContext() {
        let raw = "GET http://alice:SuperPass99@192.168.5.5:8900/external-stream/42?ticket=TICKET987&sig=SIG456&id=42 Cookie: peach_session=COOKIEVAL; tok=TOKVAL Authorization: Bearer BEARERVAL password=plainpw {\"token\":\"JSONTOK\"} %3Fticket%3DPCT999"
        let redacted = PeachLogRedactor.redactText(raw)

        for secret in ["SuperPass99", "TICKET987", "SIG456", "COOKIEVAL", "TOKVAL", "BEARERVAL", "plainpw", "JSONTOK", "PCT999"] {
            XCTAssertFalse(redacted.contains(secret), "Leaked secret \(secret) in \(redacted)")
        }
        XCTAssertTrue(redacted.contains("id=42"))
        XCTAssertTrue(redacted.contains("ticket=[REDACTED]"))
        XCTAssertTrue(redacted.contains("sig=[REDACTED]"))
        XCTAssertTrue(redacted.contains("Cookie: [REDACTED]"))
        XCTAssertTrue(redacted.contains("Authorization: [REDACTED]"))
        XCTAssertTrue(redacted.contains("password=[REDACTED]"))

        let fields = PeachLogRedactor.redactFields([
            "password": "secret-field",
            "cookie": "peach_session=abc",
            "token": "tok-123",
            "module": "avcodec",
            "url": "https://pea.wyhnb.top/external-stream/9?t=SIGN123&item=9"
        ])
        XCTAssertEqual(fields["password"], "[REDACTED]")
        XCTAssertEqual(fields["cookie"], "[REDACTED]")
        XCTAssertEqual(fields["token"], "[REDACTED]")
        XCTAssertEqual(fields["module"], "avcodec")
        XCTAssertFalse(fields["url", default: ""].contains("SIGN123"))
        XCTAssertTrue(fields["url", default: ""].contains("item=9"))
    }

    func testStoreRedactsBeforeDiskAndEnforcesOneHourRetentionWithRealFileSize() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("peach-log-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let baseNow: TimeInterval = 1_750_000_000

        let store = PeachLogStore(directory: dir, retentionSeconds: 3600, maxBatchSize: 50, nowProvider: { baseNow })
        let logFile = dir.appendingPathComponent("ios-runtime.jsonl", isDirectory: false)

        await store.append([
            .init(
                id: "old-1",
                ts: baseNow - 3550,
                level: "debug",
                category: "vlc.avcodec",
                source: "VLCLibrary",
                message: "open http://192.168.5.5:8900/external-stream/7?ticket=OLDSECRET&id=7",
                fields: ["password": "pw1", "frame": "1"]
            ),
            .init(
                id: "fresh-1",
                ts: baseNow - 10,
                level: "info",
                category: "player.avplayer",
                source: "AVPlayer",
                message: "ready id=8",
                fields: ["frame": "2"]
            )
        ], now: baseNow)

        let initialDiskText = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertFalse(initialDiskText.contains("OLDSECRET"))
        XCTAssertFalse(initialDiskText.contains("pw1"))
        XCTAssertTrue(initialDiskText.contains("[REDACTED]"))
        XCTAssertTrue(initialDiskText.contains("old-1"))
        XCTAssertTrue(initialDiskText.contains("fresh-1"))

        let snap1 = await store.snapshot(originKey: "http://192.168.5.5:8900", now: baseNow)
        let attrs1 = try FileManager.default.attributesOfItem(atPath: logFile.path)
        XCTAssertEqual(snap1.localFileBytes, (attrs1[.size] as? NSNumber)?.int64Value)
        XCTAssertEqual(snap1.totalCount, 2)
        XCTAssertNil(snap1.serverFileBytes)
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: snap1.serverFileBytes), "暂未获取")
        XCTAssertEqual(PeachLogFormatting.formatTimestamp(snap1.serverUpdatedAt), "暂未获取")

        // 100s later: old-1 is 3650s old (>1h), fresh-1 is 110s old (<1h).
        let later = baseNow + 100
        let prunedBytes = await store.pruneExpired(now: later)
        let attrs2 = try FileManager.default.attributesOfItem(atPath: logFile.path)
        XCTAssertEqual(prunedBytes, (attrs2[.size] as? NSNumber)?.int64Value)
        let diskAfterPrune = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertFalse(diskAfterPrune.contains("old-1"))
        XCTAssertTrue(diskAfterPrune.contains("fresh-1"))

        // 2 hours later: all expired.
        let muchLater = baseNow + 7200
        let finalBytes = await store.pruneExpired(now: muchLater)
        XCTAssertEqual(finalBytes, 0)
        XCTAssertEqual(try Data(contentsOf: logFile).count, 0)
    }

    func testOfflineRecoveryBackfillsOnlyNonExpiredEntriesAndPreservesServerSize() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("peach-log-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let baseNow: TimeInterval = 1_750_100_000
        let store = PeachLogStore(directory: dir, retentionSeconds: 3600, maxBatchSize: 50, nowProvider: { baseNow })
        let transport = CaptureTransport()
        let origin = "http://192.168.5.5:8900"

        await store.append([
            .init(id: "soon-expired", ts: baseNow - 3500, level: "warning", category: "vlc", source: "VLC", message: "will expire while offline", fields: [:]),
            .init(id: "still-valid", ts: baseNow - 20, level: "error", category: "api", source: "PeachAPI", message: "timeout id=12", fields: ["cookie": "peach_session=RAW"])
        ], now: baseNow)

        // Simulate offline failure.
        await transport.setFail(true)
        let failedSnap = await store.flushUploads(
            originKey: origin,
            uploader: { batch in try await transport.handle(batch) },
            now: baseNow
        )
        XCTAssertNotNil(failedSnap.lastError)
        XCTAssertNil(failedSnap.serverFileBytes)
        XCTAssertEqual(failedSnap.pendingCount, 2)

        // Network returns 200 seconds later: "soon-expired" is now 3700s old (>1h) and must not upload.
        await transport.setFail(false)
        await transport.setResponseBytes(4096)
        let recoveredTime = baseNow + 200
        let recoveredSnap = await store.flushUploads(
            originKey: origin,
            uploader: { batch in try await transport.handle(batch) },
            now: recoveredTime
        )
        XCTAssertNil(recoveredSnap.lastError)
        XCTAssertEqual(recoveredSnap.pendingCount, 0)
        XCTAssertEqual(recoveredSnap.serverFileBytes, 4096)
        XCTAssertEqual(recoveredSnap.serverUpdatedAt, recoveredTime)
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: recoveredSnap.serverFileBytes), "4.0 KB")

        let sent = await transport.sentBatches
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].entries.map(\.id), ["still-valid"])
        XCTAssertEqual(sent[0].entries[0].fields["cookie"], "[REDACTED]")

        // Re-running flush with no new logs must NOT resend or issue standalone probes.
        let idleSnap = await store.flushUploads(
            originKey: origin,
            uploader: { batch in try await transport.handle(batch) },
            now: recoveredTime + 3
        )
        let sentAfterIdle = await transport.sentBatches
        XCTAssertEqual(sentAfterIdle.count, 1)
        XCTAssertEqual(idleSnap.serverFileBytes, 4096)
    }

    func testByteAndTimestampFormattingNeverShowZeroForMissingServerValue() {
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: nil), "暂未获取")
        XCTAssertEqual(PeachLogFormatting.formatTimestamp(nil), "暂未获取")
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: 0), "0.0 KB")
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: 42), "0.04 KB")
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: 2048), "2.0 KB")
        XCTAssertEqual(PeachLogFormatting.formatFileSize(bytes: 2_621_440), "2.50 MB")
    }
}
