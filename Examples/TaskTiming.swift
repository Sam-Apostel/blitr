import SwiftUI

// `.task` work that waits: on a timer, and on the network. Rendered, `Task.sleep` runs on a virtual clock
// (delays that end within --settle-time, 2 seconds by default, pass at once; later ones wait past the
// frame), and the network is offline (a request fails at once). No "did not finish" warning, and the
// frame shows the same state every time.

struct Countdown: View {
    @State private var phase = "Preparing…"
    @State private var slide = 1

    var body: some View {
        Section("Timers") {
            LabeledContent("After 0.3 s and 1.2 s", value: phase)
            LabeledContent("Slideshow, every 5 s", value: "Slide \(slide)")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            phase = "Ready"
            try? await Task.sleep(nanoseconds: 900_000_000)
            phase = "Started"
        }
        .task {
            // A loop that never ends: its next wake-up is after the frame, so it simply waits.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                slide += 1
            }
        }
    }
}

struct Forecast: View {
    enum Load { case loading, loaded(String), failed(String) }
    @State private var load = Load.loading

    var body: some View {
        Section("Network") {
            switch load {
            case .loading: ProgressView()
            case .loaded(let text): Text(text)
            case .failed(let reason): Label(reason, systemImage: "wifi.slash")
            }
        }
        .task {
            do {
                let url = URL(string: "https://forecast.example.com/today.json")!
                let (data, _) = try await URLSession.shared.data(from: url)
                load = .loaded(String(decoding: data, as: UTF8.self))
            } catch let error as URLError where error.code == .notConnectedToInternet {
                load = .failed("Offline")
            } catch {
                load = .failed("Could not load")
            }
        }
    }
}

struct TaskTimingView: View {
    var body: some View {
        List {
            Countdown()
            Forecast()
        }
    }
}

#Preview {
    TaskTimingView()
}
