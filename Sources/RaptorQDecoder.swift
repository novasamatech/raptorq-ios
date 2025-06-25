import Foundation
import raptorq

public final class RaptorQDecoder {
    private let ctx: UnsafeMutablePointer<RQContext>

    public init?(totalBytes: UInt64, maxPayload: UInt16) {
        guard let ctx = raptorq_ctx_new(totalBytes, maxPayload) else {
            return nil
        }

        self.ctx = ctx
    }

    deinit { raptorq_ctx_free(ctx) }

    public func push(frame data: Data) -> Bool {
        data.withUnsafeBytes { buf in
            raptorq_ctx_push_frame(
                ctx,
                buf.bindMemory(to: UInt8.self).baseAddress,
                buf.count
            )
        }
    }

    public var isComplete: Bool { raptorq_ctx_is_complete(ctx) }

    public func takeResult() -> Data? {
        guard isComplete else { return nil }
        var len: Int = 0
        guard let raw = raptorq_ctx_take_result(ctx, &len) else { return nil }

        // Wrap the raw buffer without copying; free it via raptorq_free.
        return Data(bytesNoCopy: raw, count: len, deallocator: .custom { ptr, len in
            raptorq_free(ptr.assumingMemoryBound(to: UInt8.self), len)
        })
    }
}
