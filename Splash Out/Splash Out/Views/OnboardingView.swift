import SwiftUI

/// A short animated tour: shown the first time the app opens, and any time from Settings or More.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.seen") private var seen = false
    @State private var page = 0

    private struct Page {
        var symbol: String
        var tint: Color
        var title: String
        var text: String
        var demo: Demo
    }

    private enum Demo { case welcome, setup, customers, round, message, money }

    private let pages: [Page] = [
        Page(symbol: "drop.fill", tint: .blue, title: "Welcome to Splash Out",
             text: "Your customers, your round and your money in one place. Here's a quick look around.", demo: .welcome),
        Page(symbol: "person.2.fill", tint: .indigo, title: "Set up your team",
             text: "In More, then Settings, add your team, make your crews and choose your usual week.", demo: .setup),
        Page(symbol: "person.crop.circle.badge.plus", tint: .teal, title: "Add your customers",
             text: "Import a list, pick people from Contacts, or add them one at a time.", demo: .customers),
        Page(symbol: "list.clipboard.fill", tint: .green, title: "Work your round",
             text: "The Round tab lines up each day. Tap a customer, then tap what happened. It fills itself in.", demo: .round),
        Page(symbol: "message.fill", tint: .mint, title: "Book people in",
             text: "Tap Message on a day's date bar. WhatsApp opens with the message ready for each customer.", demo: .message),
        Page(symbol: "sterlingsign.circle.fill", tint: .orange, title: "Get paid, see how you're doing",
             text: "Owed shows who's waiting to pay. Stats shows your week, your tax year and more.", demo: .money),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(page == pages.count - 1 ? "" : "Skip") { finish() }
                    .padding()
                    .opacity(page == pages.count - 1 ? 0 : 1)
            }

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    PageView(symbol: item.symbol, tint: item.tint, title: item.title, text: item.text, demo: item.demo, isCurrent: page == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page == pages.count - 1 { finish() } else { withAnimation(.snappy) { page += 1 } }
            } label: {
                Text(page == pages.count - 1 ? "Get started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
        }
        .background(Color(.systemBackground))
    }

    private func finish() {
        seen = true
        dismiss()
    }

    // MARK: One page

    private struct PageView: View {
        let symbol: String
        let tint: Color
        let title: String
        let text: String
        let demo: Demo
        let isCurrent: Bool

        @State private var appeared = false

        var body: some View {
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(tint.opacity(0.14)).frame(width: 150, height: 150)
                        .scaleEffect(appeared ? 1 : 0.6)
                    Image(systemName: symbol)
                        .font(.system(size: 64))
                        .foregroundStyle(tint)
                        .symbolEffect(.bounce, value: isCurrent)
                        .scaleEffect(appeared ? 1 : 0.4)
                }
                DemoView(demo: demo, tint: tint, running: isCurrent)
                    .frame(height: 150)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 460)
                VStack(spacing: 8) {
                    Text(title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 520)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                Spacer(minLength: 0)
            }
            .onChange(of: isCurrent, initial: true) { _, current in
                if current {
                    appeared = false
                    withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
                }
            }
        }
    }

    // MARK: Little looping demos

    private struct DemoView: View {
        let demo: Demo
        let tint: Color
        let running: Bool
        @State private var step = 0

        var body: some View {
            content
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .task(id: running) {
                    guard running else { step = 0; return }
                    while !Task.isCancelled {
                        for next in 0...3 {
                            withAnimation(.easeInOut(duration: 0.4)) { step = next }
                            try? await Task.sleep(for: .seconds(0.9))
                        }
                    }
                }
        }

        @ViewBuilder
        private var content: some View {
            switch demo {
            case .welcome:
                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { index in
                        Image(systemName: ["drop.fill", "house.fill", "sterlingsign.circle.fill", "calendar"][index])
                            .font(.title)
                            .foregroundStyle(tint)
                            .opacity(step >= index ? 1 : 0.2)
                            .scaleEffect(step == index ? 1.25 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .setup:
                VStack(alignment: .leading, spacing: 8) {
                    chip("Team", "Sam, Alex", on: step >= 1)
                    chip("Crew", "Sam + Alex  £400", on: step >= 2)
                    chip("Usual week", "Mon  Tue  Wed", on: step >= 3)
                }
            case .customers:
                VStack(spacing: 8) {
                    chip("Import", "from a CSV file", on: step >= 1)
                    chip("Contacts", "name, number, address", on: step >= 2)
                    chip("Add", "one at a time", on: step >= 3)
                }
            case .round:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mon 12 Oct  ·  £448 of £440").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(0..<3, id: \.self) { index in
                        HStack {
                            Image(systemName: step > index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step > index ? .green : .secondary)
                            Text(["Anne Smith", "Barbara Evans", "Sarah Williams"][index])
                            Spacer()
                            Text(["£16", "£16", "£20"][index]).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            case .message:
                VStack(spacing: 10) {
                    HStack {
                        Text("Mon 12 Oct").font(.subheadline.bold())
                        Spacer()
                        Label(step >= 1 ? "Message" : "Message", systemImage: "message")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(tint.opacity(step == 1 ? 0.35 : 0.15), in: Capsule())
                            .scaleEffect(step == 1 ? 1.1 : 1)
                    }
                    Text("Hi Anne, we're planning to clean your windows on Monday 12 October.")
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .opacity(step >= 2 ? 1 : 0.15)
                    Image(systemName: "paperplane.fill").foregroundStyle(tint)
                        .offset(x: step >= 3 ? 70 : -70, y: step >= 3 ? -6 : 0)
                        .opacity(step >= 2 ? 1 : 0)
                }
            case .money:
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(index == 3 ? Color.orange : Color.green)
                            .frame(width: 22, height: step >= 1 ? CGFloat([50, 80, 65, 40, 95, 85][index]) : 8)
                            .animation(.spring(duration: 0.6).delay(Double(index) * 0.06), value: step)
                    }
                    Text("£").font(.largeTitle.bold()).foregroundStyle(tint).opacity(step >= 2 ? 1 : 0.2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }

        private func chip(_ title: String, _ detail: String, on: Bool) -> some View {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(tint)
                Spacer()
                Text(detail).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .opacity(on ? 1 : 0.15)
            .offset(x: on ? 0 : -14)
        }
    }
}

/// A button that opens the tour (used in Settings and More).
struct QuickTourButton: View {
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Label("Quick tour", systemImage: "sparkles")
        }
        .fullScreenCover(isPresented: $isShowing) { OnboardingView() }
    }
}

#Preview { OnboardingView() }
