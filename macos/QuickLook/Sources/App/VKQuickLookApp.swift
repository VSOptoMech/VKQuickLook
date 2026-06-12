import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "VK Quick Look")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let message = NSTextField(labelWithString: """
        This app hosts Finder thumbnail and Quick Look preview extensions for Keyence VK4/VK6 files.

        Install or rebuild it from the repository scripts to register the Finder extensions.
        """)
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.lineBreakMode = .byWordWrapping
        message.maximumNumberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(title)
        contentView.addSubview(message)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 52),
            message.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44),
            message.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -44),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22)
        ])

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "VK Quick Look"
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
