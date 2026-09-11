// EN: Select the polling policy without replacing the existing adaptive default.
// ES: Selecciona la política de sondeo sin reemplazar el valor adaptativo existente.
// 中文：选择轮询策略，同时保留现有自适应策略作为默认值。

public enum PTOBDPollingProfile: String, CaseIterable, Sendable {
    case officialYMOBD
    case adaptive

    public func makeQueue(from supportedCommands: [String]) -> [String] {
        guard !supportedCommands.isEmpty else { return [] }

        switch self {
        case .officialYMOBD:
            // EN: Reproduce the official 24-command cadence only for commands the ECU advertised.
            // ES: Reproduce la cadencia oficial de 24 comandos solo para comandos anunciados por la ECU.
            // 中文：仅对 ECU 宣布支持的指令复现官方 24 条节奏。
            let cycle = ["010C", "010D", "010C", "0105", "010C", "ATRV"]
            let officialQueue = Array(repeating: cycle, count: 4).flatMap { $0 }
            let prioritized = officialQueue.filter { supportedCommands.contains($0) }
            let remaining = supportedCommands.filter { !officialQueue.contains($0) }
            return prioritized.isEmpty ? supportedCommands : prioritized + remaining

        case .adaptive:
            let rpmCommand = "010C"
            let speedCommand = "010D"
            let otherCommands = supportedCommands.filter {
                $0 != rpmCommand && $0 != speedCommand
            }

            guard !otherCommands.isEmpty else { return supportedCommands }

            var queue: [String] = []
            queue.reserveCapacity(otherCommands.count * 3)
            for command in otherCommands {
                if supportedCommands.contains(rpmCommand) { queue.append(rpmCommand) }
                if supportedCommands.contains(speedCommand) { queue.append(speedCommand) }
                queue.append(command)
            }
            return queue
        }
    }
}
