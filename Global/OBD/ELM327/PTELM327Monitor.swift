//
//  PTELM327Monitor.swift
//  PTSpeed
//
//  EN: Keeps unsolicited ELM/CAN frames separate from command responses.
//  ES: Mantiene las tramas ELM/CAN no solicitadas separadas de las respuestas de comandos.
//  中文：将非请求的 ELM/CAN 报文与命令响应分离。
//

import Foundation

public actor PTELM327Monitor {
    private var continuation: AsyncStream<PTELM327Response>.Continuation?
    private var streamID: UUID?

    public init() {}

    public func start() -> AsyncStream<PTELM327Response> {
        continuation?.finish()
        let newStreamID = UUID()
        streamID = newStreamID
        let (stream, newContinuation) = AsyncStream<PTELM327Response>.makeStream(
            of: PTELM327Response.self,
            bufferingPolicy: .bufferingNewest(128)
        )
        // EN: Install the continuation synchronously so the first monitor frame cannot be lost after start returns.
        // ES: Instala la continuación de forma síncrona para no perder la primera trama después de devolver start.
        // 中文：同步安装 continuation，避免 start 返回后丢失第一条监听帧。
        continuation = newContinuation
        newContinuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.stop(streamID: newStreamID) }
        }
        return stream
    }

    public func yield(_ response: PTELM327Response) {
        continuation?.yield(response)
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        streamID = nil
    }
}

private extension PTELM327Monitor {
    func stop(streamID: UUID) {
        guard self.streamID == streamID else { return }
        stop()
    }
}
