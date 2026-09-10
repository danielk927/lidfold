import AppKit

/// Small settings panel: pick a style, then scale the three effects.
final class PreferencesWindow: NSWindow {

    private let stylePopUp = NSPopUpButton()
    private let perspectiveSlider = NSSlider()
    private let blurSlider = NSSlider()
    private let shadowSlider = NSSlider()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "LidFold Settings"
        isReleasedWhenClosed = false
        center()
        buildContent()
        loadValues()
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stylePopUp.addItems(withTitles: FoldStyle.allCases.map(\.displayName))
        stylePopUp.target = self
        stylePopUp.action = #selector(styleChanged)
        stack.addArrangedSubview(labelled("Style", stylePopUp))

        for (title, slider) in [
            ("Perspective", perspectiveSlider),
            ("Blur", blurSlider),
            ("Shadow", shadowSlider),
        ] {
            slider.minValue = 0
            slider.maxValue = 1
            slider.target = self
            slider.action = #selector(sliderChanged)
            slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
            stack.addArrangedSubview(labelled(title, slider))
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        contentView = content
    }

    private func labelled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    private func loadValues() {
        let settings = FoldSettings.shared
        stylePopUp.selectItem(withTitle: settings.style.displayName)
        perspectiveSlider.doubleValue = settings.perspective
        blurSlider.doubleValue = settings.blur
        shadowSlider.doubleValue = settings.shadow
    }

    @objc private func styleChanged() {
        guard let title = stylePopUp.titleOfSelectedItem,
              let style = FoldStyle.allCases.first(where: { $0.displayName == title })
        else { return }
        FoldSettings.shared.style = style
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let settings = FoldSettings.shared
        switch sender {
        case perspectiveSlider: settings.perspective = sender.doubleValue
        case blurSlider:        settings.blur = sender.doubleValue
        case shadowSlider:      settings.shadow = sender.doubleValue
        default: break
        }
    }
}
