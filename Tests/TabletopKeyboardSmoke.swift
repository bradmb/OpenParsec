import UIKit
import ObjectiveC

// Test transport only: the simulator cannot load the device-only Parsec SDK.
let PARSEC_OK = 0
enum CParsec {
	static var events: [TabletopKeyEvent] = []
	static func getStatus() -> Int { PARSEC_OK }
	static func sendKeyboardMessage(keyCode: UInt32, pressed: Bool) {
		events.append(TabletopKeyEvent(code: keyCode, pressed: pressed))
	}
}

@main
final class KeyboardSmokeApp: UIResponder, UIApplicationDelegate {
	var window: UIWindow?
	private var ran = false

	func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		let window = UIWindow(frame: UIScreen.main.bounds)
		window.rootViewController = UIViewController()
		window.makeKeyAndVisible()
		self.window = window
		return true
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		guard !ran else { return }
		ran = true
		DispatchQueue.main.async { self.runChecks() }
	}

	private func runChecks() {
		let keyboard = TabletopKeyboard()
		keyboard.enabled = true
		let panel = TabletopKeyboardPanel(keyboard: keyboard)
		panel.frame = CGRect(x: 0, y: 0, width: 951, height: 320)
		window!.rootViewController!.view.addSubview(panel)
		panel.layoutIfNeeded()
		func descendants(_ view: UIView) -> [UIView] {
			[view] + view.subviews.flatMap(descendants)
		}
		let buttons = descendants(panel).compactMap { $0 as? UIButton }
		precondition(buttons.count == 60, "All desktop keys must construct without hanging")
		for width: CGFloat in [951, 669, 658, 669, 951] {
			panel.frame.size.width = width
			panel.setNeedsLayout()
			panel.layoutIfNeeded()
			for button in buttons {
				let frame = button.convert(button.bounds, to: panel)
				precondition(frame.minX >= 7.9 && frame.maxX <= width - 7.9,
							 "Every key must fit the pane horizontally at width \(width): \(button.accessibilityIdentifier ?? "") \(frame)")
				precondition(frame.minY >= 7.9 && frame.maxY <= panel.bounds.height - 7.9, "Every row fits vertically")
				precondition(button.bounds.width >= 43.9 && button.bounds.height >= 44,
							 "Resizing preserves touch targets at \(width): \(button.accessibilityIdentifier ?? "") \(button.bounds)")
			}
		}
		for button in buttons {
			precondition(button.bounds.width >= 43.9 && button.bounds.height >= 44, "Minimum touch target")
			let selector = NSSelectorFromString("release")
			let actual = method_getImplementation(class_getInstanceMethod(type(of: button), selector)!)
			let inherited = method_getImplementation(class_getInstanceMethod(UIButton.self, selector)!)
			precondition(unsafeBitCast(actual, to: UInt.self) == unsafeBitCast(inherited, to: UInt.self),
						 "Keyboard actions must not override NSObject release")
		}
		func key(_ code: UInt32) -> UIButton {
			buttons.first { $0.accessibilityIdentifier == "tabletop.key.\(code)" }!
		}
		let a = key(4)
		a.sendActions(for: .touchDown)
		a.sendActions(for: .touchUpInside)
		precondition(CParsec.events == [TabletopKeyEvent(code: 4, pressed: true), TabletopKeyEvent(code: 4, pressed: false)])
		let shift = key(225)
		shift.sendActions(for: .touchDown)
		shift.sendActions(for: .touchUpInside)
		precondition(keyboard.state.held.contains(225) && shift.isSelected && a.title(for: .normal) == "A")
		a.sendActions(for: .touchCancel)
		precondition(keyboard.state.held.isEmpty && !shift.isSelected)
		shift.sendActions(for: .touchDown)
		keyboard.releaseAll()
		shift.sendActions(for: .touchUpInside)
		precondition(keyboard.state.held.isEmpty, "An interrupted modifier tap cannot relatch")
		precondition(a.accessibilityActivate())
		precondition(keyboard.state.held.isEmpty, "VoiceOver activation sends a balanced key pair")
		let backspace = key(42)
		backspace.sendActions(for: .touchDown)
		let beforeRepeat = CParsec.events.count
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
			precondition(CParsec.events.count > beforeRepeat, "Held Backspace repeats")
			backspace.sendActions(for: .touchCancel)
			let afterCancel = CParsec.events.count
			precondition(keyboard.state.held.isEmpty && keyboard.state.repeating.isEmpty)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
				precondition(CParsec.events.count == afterCancel, "Cancelled repeat timer stays stopped")
				panel.removeFromSuperview()
				print("TABLETOP_UI_SMOKE_PASSED")
				fflush(stdout)
				exit(0)
			}
		}
	}
}
