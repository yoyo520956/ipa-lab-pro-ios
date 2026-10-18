import SwiftUI

private struct DS { static let red = Color.red }

private struct PseudoLine: Identifiable, Hashable {
    let id: Int
    let text: String
    let address: UInt64?
}

private struct InstructionEntry: Identifiable, Hashable {
    let id: Int
    let address: UInt64
}

private enum DisasmService {
    static func pseudocode(for i: [InstructionEntry]) -> [String] { [] }
}

private final class Engine: ObservableObject {
    @Published var instructions: [InstructionEntry] = []
}

private struct DisasmTab: View {
    @StateObject private var engine = Engine()
    @State private var running = false
    @State private var errorText: String?
    @State private var showPseudocode = true
    @State private var instructions: [InstructionEntry] = []

    static func makePseudoLines(_ l: [String], _ i: [InstructionEntry]) -> [PseudoLine] { [] }

    var body: some View {
        VStack {
            if running { ProgressView().padding() }
            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(DS.red)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if showPseudocode {
                        let pseudoLines = DisasmService.pseudocode(for: instructions)
                        let lineModels: [PseudoLine] = Self.makePseudoLines(pseudoLines, instructions)
                        ForEach(lineModels, id: \.self) { lm in
                            Text(lm.text)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                            if let addr = lm.address {
                                Text("0x\(String(addr, radix: 16))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        ForEach(instructions) { insn in
                            Text("0x\(String(insn.address, radix: 16))")
                        }
                    }
                }
            }
        }
    }
}
