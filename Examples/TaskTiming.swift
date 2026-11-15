import SwiftUI

// `.task` work that waits: on a timer, and on the network. Rendered, `Task.sleep` runs on a virtual clock
// (delays that end within --settle-time, 2 seconds by default, pass at once; later ones wait past the
// frame), and the network is offline (a request fails at once). No "did not finish" warning, and the
// frame shows the same state every time.

struct Countdown: View {
    @State private var phase = "Preparing…"
    @State private var slide = 1
    @State private var tick = "Waiting…"

    var body: some View {
        Section("Timers") {
            LabeledContent("After 0.3 s and 1.2 s", value: phase)
            LabeledContent("Slideshow, every 5 s", value: "Slide \(slide)")
            LabeledContent("On a clock, after 1 s", value: tick)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            phase = "Ready"
            try? await Task.sleep(nanoseconds: 900_000_000)
            phase = "Started"
        }
        .task {
            let clock = ContinuousClock()
            try? await clock.sleep(for: .seconds(1))
            tick = "Done"
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
    /// A session with its own configuration, as API clients usually make.
    var session: URLSession = .shared
    var title = "Network"

    var body: some View {
        Section(title) {
            switch load {
            case .loading: ProgressView()
            case .loaded(let text): Text(text)
            case .failed(let reason): Label(reason, systemImage: "wifi.slash")
            }
        }
        .task {
            do {
                let url = URL(string: "https://forecast.example.com/today.json")!
                let (data, _) = try await session.data(from: url)
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
            Forecast(session: URLSession(configuration: .ephemeral), title: "Network, own session")
        }
    }
}

#Preview {
    TaskTimingView()
}
