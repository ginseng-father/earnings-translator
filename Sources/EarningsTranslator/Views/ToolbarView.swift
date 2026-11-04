import SwiftUI
import TranslatorSystem

struct ToolbarView: View {
    @Bindable var session: SessionController
    @Bindable var settings: Settings

    var body: some View {
        HStack(spacing: 8) {
            Picker("브라우저", selection: $session.selectedBrowser) {
                if session.browsers.isEmpty {
                    Text("실행 중인 브라우저 없음").tag(Browser?.none)
                }
                ForEach(session.browsers) { browser in
                    Text(browser.name).tag(Optional(browser))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 110)
            .disabled(session.isRunning)
            .onTapGesture { session.refreshBrowsers() }

            Picker("모델", selection: $settings.modelTag) {
                ForEach(Settings.models, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(minWidth: 140)
            .disabled(session.isRunning)

            Spacer()

            Button(session.isRunning ? "정지" : "시작") {
                Task { session.isRunning ? await session.stop() : await session.start() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(session.isRunning ? .red : .accentColor)
            .disabled(session.selectedBrowser == nil)

            Button("저장") {
                Task { await session.saveNow() }
            }
            .disabled(session.segments.isEmpty)

            Toggle(isOn: $settings.pinOnTop) {
                Image(systemName: settings.pinOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help("다른 창 위에 항상 표시")
        }
        .padding(10)
    }
}
