import SwiftUI
import UIKit

// Measures the frame SwiftUI gives `Image(systemName:)` for every name in the bundled names.txt, at each
// requested point size, weight and image scale, and writes Documents/frames.tsv, then Documents/done.
// Built and driven by scripts/mac/measure-symbol-frames.sh.
//
// Each image sits at the top-left corner of its own fixed 512pt cell, so its origin is on the pixel grid
// and its size is not perturbed by the fractional position of a neighbour. Images are measured a batch at
// a time; GeometryReader reports each one's laid-out size.

struct Job: Hashable {
    let name: String
    let size: CGFloat
    let weight: String
    let scale: String
}

let weights: [String: Font.Weight] = [
    "ultralight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
    "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black,
]
let scales: [String: Image.Scale] = ["small": .small, "medium": .medium, "large": .large]

func makeJobs() -> [Job] {
    let names = (try? String(contentsOf: Bundle.main.url(forResource: "names", withExtension: "txt")!, encoding: .utf8))?
        .split(separator: "\n").map(String.init) ?? []
    // Configurations: "<size> <weight> <scale>" per line.
    let configs = (try? String(contentsOf: Bundle.main.url(forResource: "configs", withExtension: "txt")!, encoding: .utf8))?
        .split(separator: "\n").map { $0.split(separator: " ").map(String.init) } ?? []
    var jobs: [Job] = []
    for c in configs where c.count >= 3 {
        // An optional fourth field limits the configuration to the first N names.
        let limit = c.count > 3 ? Int(c[3]) ?? names.count : names.count
        for name in names.prefix(limit) {
            jobs.append(Job(name: name, size: CGFloat(Double(c[0]) ?? 100), weight: c[1], scale: c[2]))
        }
    }
    return jobs
}

struct SizeKey: PreferenceKey {
    static let defaultValue: [Int: CGSize] = [:]
    static func reduce(value: inout [Int: CGSize], nextValue: () -> [Int: CGSize]) { value.merge(nextValue()) { $1 } }
}

@MainActor final class Measurer: ObservableObject {
    let jobs = makeJobs()
    let batchSize = 120
    @Published var start = 0
    var lines: [String] = []
    var recorded = -1
    let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    var batch: ArraySlice<Job> { jobs[start..<min(start + batchSize, jobs.count)] }

    func record(_ sizes: [Int: CGSize]) {
        let current = Array(batch.enumerated())
        guard !current.isEmpty, start != recorded,
              current.allSatisfy({ sizes[start + $0.offset] != nil }) else { return }
        recorded = start
        for (i, job) in current {
            let s = sizes[start + i] ?? .zero
            let exists = UIImage(systemName: job.name) != nil
            lines.append("\(job.name)\t\(Int(job.size))\t\(job.weight)\t\(job.scale)\t\(s.width)\t\(s.height)\t\(exists ? 1 : 0)")
        }
        let next = start + batchSize
        if next >= jobs.count {
            try? (lines.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("frames.tsv"), atomically: true, encoding: .utf8)
            try? Data("ok".utf8).write(to: out.appendingPathComponent("done"))
        } else {
            // Let this batch's views go before the next one is laid out.
            DispatchQueue.main.async { self.start = next }
        }
    }
}

@main
struct SymbolFramesApp: App {
    @StateObject private var measurer = Measurer()

    var body: some Scene {
        WindowGroup {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(measurer.batch.enumerated()), id: \.offset) { i, job in
                        Image(systemName: job.name)
                            .font(.system(size: job.size, weight: weights[job.weight] ?? .regular))
                            .imageScale(scales[job.scale] ?? .medium)
                            .fixedSize()
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: SizeKey.self, value: [measurer.start + i: proxy.size])
                            })
                            .frame(width: 512, height: 512, alignment: .topLeading)
                    }
                }
                .id(measurer.start)
            }
            .onPreferenceChange(SizeKey.self) { sizes in
                MainActor.assumeIsolated { measurer.record(sizes) }
            }
        }
    }
}
