// Interaction scripts and animation capture (docs/INTERACTION.md).
//
// Each preview below is driven by a short script. Run from the repository root; `S` is
// `blitr render Examples/Interactions.swift`.
//
//   S --preview Counter -o out/counter.png --filmstrip out/counter-strip.png \
//       --steps 'tap "Increment"; tap "Increment"; tap "Decrement"; tap "Reset"'
//
//   S --preview Todos -o out/todos.png --frames out/todos --frames-every-step --animated out/todos.gif \
//       --steps 'type "New task" "Water the plants" submit; tap "Buy milk"; swipe "Call the dentist" left; set "Show completed" off'
//
//   S --preview "Sign Up" -o out/signup.png --filmstrip out/signup-strip.png \
//       --steps 'type "Email" "sam@"; tap "Create account"; snapshot error; type "Email" "sam@example.com"; type "Password" "correct horse"; tap "Create account"; snapshot welcome'
//
//   S --preview Presentations -o out/presentations.png --animated out/presentations.gif \
//       --steps 'tap "Show details"; tap "Done"; tap "Delete everything"; tap "Cancel"'
//
//   S --preview Navigation -o out/navigation.png --animated out/navigation.gif \
//       --steps 'tap "Mercury"; back; tap "Venus"; tap "Favourite"; back'
//
//   S --preview "Expanding Card" -o out/card.png --animated out/card.gif --filmstrip out/card-strip.png --filmstrip-frames 6 \
//       --steps 'tap "Trip to Lisbon"; wait 0.4; tap "Trip to Lisbon"'
//
//   S --preview Hero -o out/hero.png --animated out/hero.gif --steps 'tap "Aurora"; wait 0.5; tap "Close"'
//
//   S --preview Inbox -o out/inbox.png --animated out/inbox.gif --steps 'tap "New message"; tap "New message"; tap "Archive first"'
//
//   S --preview Loading -o out/loading.png --animated out/loading.gif --duration 2 --hold 0
//
//   S --preview Pulse -o out/pulse.png --animated out/pulse.apng --duration 3 --hold 0     # APNG
//
// Add `--animated-scale 0.5`, `--fps 60`, `--scale 1` or another extension (.png for APNG, .webp, .mp4) to
// taste. `--frames-all` with `--frames <dir>` writes every in-between frame as a PNG.

import SwiftUI

// MARK: - Counter

struct CounterDemo: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack(spacing: 16) {
                Button { count -= 1 } label: { Label("Decrement", systemImage: "minus") }
                    .buttonStyle(.bordered)
                Button { count += 1 } label: { Label("Increment", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            Button("Reset", role: .destructive) { count = 0 }
                .disabled(count == 0)
        }
        .padding()
    }
}

#Preview("Counter") { CounterDemo() }

// MARK: - Todo list

struct Todo: Identifiable {
    let id = UUID()
    var title: String
    var done = false
}

struct TodosDemo: View {
    @State private var todos = [Todo(title: "Buy milk"), Todo(title: "Call the dentist"), Todo(title: "Book flights", done: true)]
    @State private var draft = ""
    @State private var showCompleted = true

    private var visible: [Todo] { todos.filter { showCompleted || !$0.done } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New task", text: $draft)
                        .onSubmit(add)
                    Toggle("Show completed", isOn: $showCompleted)
                }
                Section("\(todos.filter { !$0.done }.count) to do") {
                    ForEach(visible) { todo in
                        HStack {
                            Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(todo.done ? Color.green : Color.secondary)
                            Text(todo.title)
                                .strikethrough(todo.done)
                                .foregroundStyle(todo.done ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(todo) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { visible[$0].id }
                        todos.removeAll { ids.contains($0.id) }
                    }
                }
            }
            .navigationTitle("Todos")
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        todos.insert(Todo(title: title), at: 0)
        draft = ""
    }

    private func toggle(_ todo: Todo) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].done.toggle()
    }
}

#Preview("Todos") { TodosDemo() }

// MARK: - Form with validation

struct SignUpDemo: View {
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var created = false

    var body: some View {
        Form {
            Section("Account") {
                TextField("Email", text: $email)
                SecureField("Password", text: $password)
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button("Create account", action: submit)
            }
            if created {
                Section {
                    Label("Welcome, \(email)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func submit() {
        created = false
        if !email.contains("@") || !email.contains(".") {
            error = "Enter a valid email address"
        } else if password.count < 8 {
            error = "The password needs at least 8 characters"
        } else {
            error = nil
            created = true
        }
    }
}

#Preview("Sign Up") { SignUpDemo() }

// MARK: - Sheet and alert

struct PresentationsDemo: View {
    @State private var showsDetails = false
    @State private var confirmsDelete = false
    @State private var deleted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: deleted ? "trash.slash" : "folder.fill")
                .font(.system(size: 56))
                .foregroundStyle(deleted ? Color.secondary : Color.blue)
            Text(deleted ? "Nothing left" : "12 documents")
                .font(.title2.weight(.semibold))
            Button("Show details") { showsDetails = true }
                .buttonStyle(.borderedProminent)
            Button("Delete everything", role: .destructive) { confirmsDelete = true }
        }
        .sheet(isPresented: $showsDetails) {
            DetailsSheet()
                .presentationDetents([.medium])
        }
        .alert("Delete all documents?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) { deleted = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct DetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Documents", value: "12")
                LabeledContent("Size", value: "48 MB")
                LabeledContent("Modified", value: "Today")
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Presentations") { PresentationsDemo() }

// MARK: - Navigation push

struct Planet: Identifiable, Hashable {
    let id: String
    var name: String { id }
    let fact: String
    let color: Color
}

struct NavigationDemo: View {
    let planets = [
        Planet(id: "Mercury", fact: "A year lasts 88 days.", color: .gray),
        Planet(id: "Venus", fact: "A day is longer than its year.", color: .orange),
        Planet(id: "Earth", fact: "The only one with open oceans.", color: .blue),
        Planet(id: "Mars", fact: "Home of the tallest volcano.", color: .red),
    ]
    @State private var favourites: Set<String> = []

    var body: some View {
        NavigationStack {
            List(planets) { planet in
                NavigationLink(value: planet) {
                    Label {
                        Text(planet.name)
                    } icon: {
                        Image(systemName: favourites.contains(planet.id) ? "star.fill" : "circle.fill")
                            .foregroundStyle(planet.color)
                    }
                }
            }
            .navigationTitle("Planets")
            .navigationDestination(for: Planet.self) { planet in
                VStack(spacing: 16) {
                    Circle().fill(planet.color.gradient).frame(width: 140, height: 140)
                    Text(planet.fact).font(.headline)
                    Toggle("Favourite", isOn: Binding(
                        get: { favourites.contains(planet.id) },
                        set: { on in if on { favourites.insert(planet.id) } else { favourites.remove(planet.id) } }))
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .padding(.top, 32)
                .navigationTitle(planet.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

#Preview("Navigation") { NavigationDemo() }

// MARK: - Expanding card (withAnimation(.spring))

struct ExpandingCardDemo: View {
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "airplane")
                        .font(.title2)
                        .rotationEffect(.degrees(expanded ? -45 : 0))
                    Text("Trip to Lisbon").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("12 – 19 June").font(.subheadline)
                        Text("Flight TP 643 leaves at 09:40 from gate B12. The hotel is a ten minute walk from Rossio station.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(expanded ? 24 : 16)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: expanded ? 28 : 14).fill(expanded ? Color.indigo : Color.blue))
            .shadow(color: .black.opacity(expanded ? 0.3 : 0.1), radius: expanded ? 16 : 4, y: expanded ? 8 : 2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { expanded.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            Text("Tap the card")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

#Preview("Expanding Card") { ExpandingCardDemo() }

// MARK: - matchedGeometryEffect hero

struct HeroDemo: View {
    @Namespace private var hero
    @State private var selected: String?
    let items: [(name: String, color: Color)] = [("Aurora", .teal), ("Dunes", .orange), ("Forest", .green), ("Harbor", .indigo)]

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Places").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(items, id: \.name) { item in
                        if selected != item.name {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(item.color.gradient)
                                .matchedGeometryEffect(id: item.name, in: hero)
                                .frame(height: 120)
                                .overlay(alignment: .bottomLeading) {
                                    Text(item.name).font(.headline).foregroundStyle(.white).padding(12)
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { selected = item.name }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                        } else {
                            Color.clear.frame(height: 120)
                        }
                    }
                }
                Spacer()
            }
            .padding()

            if let name = selected, let item = items.first(where: { $0.name == name }) {
                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(item.color.gradient)
                        .matchedGeometryEffect(id: item.name, in: hero)
                        .frame(height: 360)
                    Text(item.name).font(.largeTitle.bold())
                    Text("A place worth the detour, best seen just after sunrise.")
                        .foregroundStyle(.secondary)
                    Button("Close") {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { selected = nil }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .transition(.opacity)
            }
        }
    }
}

#Preview("Hero") { HeroDemo() }

// MARK: - List insertion with a transition

struct InboxDemo: View {
    struct Message: Identifiable {
        let id: Int
        let sender: String
        let subject: String
    }

    @State private var messages = [Message(id: 1, sender: "Ada", subject: "Lunch on Friday?"),
                                   Message(id: 2, sender: "Linus", subject: "Patch review")]
    @State private var nextID = 3
    private let incoming = [("Grace", "Compiler notes"), ("Alan", "Enigma variations"), ("Margaret", "Flight software")]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("New message") {
                    let (sender, subject) = incoming[(nextID - 3) % incoming.count]
                    withAnimation(.snappy) { messages.insert(Message(id: nextID, sender: sender, subject: subject), at: 0) }
                    nextID += 1
                }
                .buttonStyle(.borderedProminent)
                Button("Archive first") {
                    withAnimation(.easeInOut(duration: 0.35)) { if !messages.isEmpty { messages.removeFirst() } }
                }
                .buttonStyle(.bordered)
            }
            ForEach(messages) { message in
                HStack(spacing: 12) {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 40, height: 40)
                        .overlay(Text(String(message.sender.prefix(1))).font(.headline).foregroundStyle(.blue))
                    VStack(alignment: .leading) {
                        Text(message.sender).font(.headline)
                        Text(message.subject).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)))
            }
            Spacer()
        }
        .padding()
    }
}

#Preview("Inbox") { InboxDemo() }

// MARK: - Time-driven content (--duration)

struct LoadingDemo: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            ProgressView("Loading your library")
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .symbolEffect(.rotate)
            Image(systemName: "wifi")
                .font(.largeTitle)
                .symbolEffect(.pulse)
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 12 + 18 * abs(sin(t * 3 + Double(i) * 0.6)))
                    }
                }
                .frame(height: 32)
            }
        }
        .padding()
    }
}

#Preview("Loading") { LoadingDemo() }

struct PulseDemo: View {
    enum Phase: CaseIterable { case rest, grow, glow }

    var body: some View {
        VStack(spacing: 40) {
            PhaseAnimator(Phase.allCases) { phase in
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(phase == .glow ? Color.pink : Color.red)
                    .scaleEffect(phase == .rest ? 1 : 1.25)
                    .shadow(color: .pink.opacity(phase == .glow ? 0.6 : 0), radius: 18)
            } animation: { phase in
                switch phase {
                case .rest: .easeOut(duration: 0.5)
                case .grow: .spring(response: 0.3, dampingFraction: 0.5)
                case .glow: .easeInOut(duration: 0.4)
                }
            }

            KeyframeAnimator(initialValue: CGFloat(0)) { offset in
                Circle().fill(Color.blue).frame(width: 28, height: 28).offset(y: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-60, duration: 0.35)
                    CubicKeyframe(0, duration: 0.35)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
        .padding()
    }
}

#Preview("Pulse") { PulseDemo() }
