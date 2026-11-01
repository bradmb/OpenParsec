import SwiftUI
import UIKit
import ParsecSDK

final class TabletopKeyboard {
	private(set) var state = TabletopKeyState()
	private var timers: [UInt32: Timer] = [:]
	var onChange: (() -> Void)?
	var enabled = false {
		didSet { if !enabled { releaseAll() } }
	}

	private var canSend: Bool {
		enabled && UIApplication.shared.applicationState == .active && CParsec.getStatus() == PARSEC_OK
	}

	func press(_ code: UInt32, repeats: Bool) {
		guard canSend else { releaseAll(); return }
		if TabletopKeyState.modifiers.contains(code) {
			send(state.toggleModifier(code))
		} else {
			send(state.press(code, repeats: repeats))
			if repeats, timers[code] == nil {
				let timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
					guard let self = self else { return }
					guard self.canSend else { self.releaseAll(); return }
					self.send(self.state.repeatEvents(code))
				}
				timer.fireDate = Date().addingTimeInterval(0.4)
				timers[code] = timer
				RunLoop.main.add(timer, forMode: .common)
			}
		}
		onChange?()
	}

	func release(_ code: UInt32) {
		guard !TabletopKeyState.modifiers.contains(code) else { return }
		timers.removeValue(forKey: code)?.invalidate()
		send(state.release(code))
		onChange?()
	}

	func releaseAll(sendToHost: Bool = true) {
		timers.values.forEach { $0.invalidate() }
		timers.removeAll()
		let events = state.releaseAll()
		if sendToHost { send(events) }
		onChange?()
	}

	private func send(_ events: [TabletopKeyEvent]) {
		for event in events {
			CParsec.sendKeyboardMessage(keyCode: event.code, pressed: event.pressed)
		}
	}

	deinit { timers.values.forEach { $0.invalidate() } }
}

struct TabletopKeyboardView: UIViewRepresentable {
	let keyboard: TabletopKeyboard

	func makeUIView(context: Context) -> TabletopKeyboardPanel {
		TabletopKeyboardPanel(keyboard: keyboard)
	}

	func updateUIView(_ uiView: TabletopKeyboardPanel, context: Context) {}

	static func dismantleUIView(_ uiView: TabletopKeyboardPanel, coordinator: ()) {
		uiView.keyboard.releaseAll()
		uiView.keyboard.onChange = nil
	}
}

final class TabletopKeyboardPanel: UIView {
	let keyboard: TabletopKeyboard
	private let scroll = UIScrollView()
	private let rows = UIStackView()
	private var buttons: [TabletopKeyButton] = []
	private var rowsWidth: NSLayoutConstraint!
	private var rowsHeight: NSLayoutConstraint!

	init(keyboard: TabletopKeyboard) {
		self.keyboard = keyboard
		super.init(frame: .zero)
		backgroundColor = UIColor(white: 0.08, alpha: 1)
		accessibilityIdentifier = "tabletop.keyboard"
		scroll.delaysContentTouches = false
		scroll.canCancelContentTouches = true
		scroll.contentInsetAdjustmentBehavior = .never
		scroll.isDirectionalLockEnabled = true
		scroll.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scroll)
		rows.axis = .vertical
		rows.spacing = 6
		rows.distribution = .fillEqually
		rows.translatesAutoresizingMaskIntoConstraints = false
		scroll.addSubview(rows)
		rowsWidth = rows.widthAnchor.constraint(equalToConstant: 690)
		rowsHeight = rows.heightAnchor.constraint(equalToConstant: 244)
		NSLayoutConstraint.activate([
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			scroll.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
			rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
			rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
			rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
			rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
			rowsWidth, rowsHeight
		])

		typealias Key = TabletopKeyButton.Spec
		func letters(_ text: String) -> [Key] {
			text.utf8.map { Key(String(UnicodeScalar($0)), UInt32($0 - 97 + 4)) }
		}
		var numberRow = [Key("Esc", 41)]
		for (index, pair) in zip("1234567890", "!@#$%^&*()").enumerated() {
			numberRow.append(Key(String(pair.0), UInt32(30 + index), shifted: String(pair.1)))
		}
		numberRow += [Key("-", 45, shifted: "_"), Key("=", 46, shifted: "+"), Key("⌫", 42, name: "Backspace", repeats: true)]
		var topRow = [Key("Tab", 43)] + letters("qwertyuiop")
		topRow += [Key("[", 47, shifted: "{"), Key("]", 48, shifted: "}"), Key("\\", 49, shifted: "|")]
		var homeRow = [Key("Ctrl", 224, name: "Control")] + letters("asdfghjkl")
		homeRow += [Key(";", 51, shifted: ":"), Key("'", 52, shifted: "\""), Key("Enter", 40)]
		var lowerRow = [Key("Shift", 225), Key("`", 53, shifted: "~")] + letters("zxcvbnm")
		lowerRow += [Key(",", 54, shifted: "<"), Key(".", 55, shifted: ">"), Key("/", 56, shifted: "?"), Key("↑", 82, name: "Up arrow", repeats: true)]
		let bottomRow = [Key("Alt", 226), Key("Win/⌘", 227, name: "Windows or Command"), Key("Space", 44, weight: 6),
						 Key("←", 80, name: "Left arrow", repeats: true), Key("↓", 81, name: "Down arrow", repeats: true), Key("→", 79, name: "Right arrow", repeats: true)]
		let specs = [numberRow, topRow, homeRow, lowerRow, bottomRow]
		for specs in specs {
			let row = UIStackView()
			row.spacing = 5
			var first: TabletopKeyButton?
			for spec in specs {
				let button = TabletopKeyButton(spec: spec, keyboard: keyboard)
				buttons.append(button)
				row.addArrangedSubview(button)
				if let first = first {
					button.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: spec.weight / first.spec.weight).isActive = true
				} else {
					first = button
				}
			}
			rows.addArrangedSubview(row)
		}
		keyboard.onChange = { [weak self] in self?.refresh() }
		refresh()
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		// Tighten gaps before scrolling: the Duo's 669pt pane fits 14 full-size
		// keys, but not the wider desktop spacing plus the outer padding.
		let availableWidth = max(0, bounds.width - 16)
		let gap = floor(min(5, max(2, (availableWidth - 14 * 44) / 13)))
		for case let row as UIStackView in rows.arrangedSubviews where row.spacing != gap {
			row.spacing = gap
		}
		let width = max(14 * 44 + 13 * gap, availableWidth)
		let height = max(5 * 44 + 4 * 6, bounds.height - 16)
		if rowsWidth.constant != width { rowsWidth.constant = width }
		if rowsHeight.constant != height { rowsHeight.constant = height }
		super.layoutSubviews()
		if width <= availableWidth, scroll.contentOffset.x != 0 {
			scroll.contentOffset.x = 0
		}
	}

	private func refresh() {
		let shifted = keyboard.state.held.contains(225)
		for button in buttons {
			let spec = button.spec
			let title = shifted ? (spec.shifted ?? (spec.code >= 4 && spec.code <= 29 ? spec.title.uppercased() : spec.title)) : spec.title
			button.setTitle(title, for: .normal)
			button.accessibilityLabel = spec.name ?? title
			button.isSelected = keyboard.state.held.contains(spec.code)
			button.backgroundColor = button.isSelected ? .systemBlue : UIColor(white: 0.22, alpha: 1)
			button.accessibilityValue = TabletopKeyState.modifiers.contains(spec.code) ? (button.isSelected ? "On" : "Off") : nil
		}
	}
}

private final class TabletopKeyButton: UIButton {
	struct Spec {
		let title: String
		let code: UInt32
		var shifted: String?
		var name: String?
		var repeats: Bool
		var weight: CGFloat

		init(_ title: String, _ code: UInt32, shifted: String? = nil, name: String? = nil, repeats: Bool = false, weight: CGFloat = 1) {
			self.title = title
			self.code = code
			self.shifted = shifted
			self.name = name
			self.repeats = repeats
			self.weight = weight
		}
	}

	let spec: Spec
	private let keyboard: TabletopKeyboard
	private var touchGeneration: UInt?

	init(spec: Spec, keyboard: TabletopKeyboard) {
		self.spec = spec
		self.keyboard = keyboard
		super.init(frame: .zero)
		setTitleColor(.white, for: .normal)
		titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
		titleLabel?.adjustsFontSizeToFitWidth = true
		titleLabel?.minimumScaleFactor = 0.7
		layer.cornerRadius = 6
		isExclusiveTouch = false
		accessibilityIdentifier = "tabletop.key.\(spec.code)"
		addTarget(self, action: #selector(handleKeyTouchBegan), for: .touchDown)
		if TabletopKeyState.modifiers.contains(spec.code) {
			accessibilityHint = "Tap to toggle. Tap again to release."
			addTarget(self, action: #selector(handleModifierTouchEnded), for: .touchUpInside)
		} else {
			addTarget(self, action: #selector(handleKeyTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchDragExit])
		}
		addTarget(self, action: #selector(handleKeyTouchCancelled), for: .touchCancel)
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	@objc private func handleKeyTouchBegan() {
		touchGeneration = keyboard.state.generation
		if !TabletopKeyState.modifiers.contains(spec.code) { keyboard.press(spec.code, repeats: spec.repeats) }
	}
	@objc private func handleModifierTouchEnded() {
		guard touchGeneration == keyboard.state.generation else { return }
		keyboard.press(spec.code, repeats: false)
	}
	@objc private func handleKeyTouchEnded() { keyboard.release(spec.code) }
	@objc private func handleKeyTouchCancelled() { keyboard.releaseAll() }

	override func accessibilityActivate() -> Bool {
		keyboard.press(spec.code, repeats: false)
		handleKeyTouchEnded()
		return true
	}
}
