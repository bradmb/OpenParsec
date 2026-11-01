import Foundation
import CoreGraphics

enum TabletopRegressionTests {
	static func run(check: (Bool, String) -> Void) {
		let bounds = CGRect(x: 0, y: 0, width: 800, height: 720)
		let fold = CGRect(x: -20, y: 350, width: 840, height: 20)
		let split = TabletopLayout.resolve(isDuo: true, bounds: bounds, divisions: [fold])
		check(split?.video == CGRect(x: 0, y: 0, width: 800, height: 350), "tabletop video ends before supplied fold margin")
		check(split?.keyboard == CGRect(x: 0, y: 370, width: 800, height: 350), "tabletop keyboard starts after supplied fold margin")
		check(TabletopLayout.resolve(isDuo: false, bounds: bounds, divisions: [fold]) == nil, "tabletop never activates on non-Duo")
		check(TabletopLayout.resolve(isDuo: true, bounds: bounds, divisions: []) == nil, "flat posture does not split")
		for invalid in [
			CGRect(x: 390, y: -20, width: 20, height: 800),
			CGRect(x: 0, y: 350, width: 800, height: 0),
			CGRect(x: 0, y: 800, width: 800, height: 20),
			CGRect(x: 0, y: -20, width: 800, height: 20),
			CGRect(x: 50, y: 350, width: 700, height: 20),
			CGRect(x: 0, y: 60, width: 800, height: 20),
			CGRect(x: 0, y: 650, width: 800, height: 20)
		] {
			check(TabletopLayout.resolve(isDuo: true, bounds: bounds, divisions: [invalid]) == nil,
				  "vertical, inactive, offscreen, partial-width and cramped divisions rejected")
		}
		check(TabletopLayout.resolve(isDuo: true, bounds: .zero, divisions: [fold]) == nil, "empty tabletop bounds rejected")
		check(TabletopLayout.resolve(isDuo: true, bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 720), divisions: [fold]) == nil,
			  "nonfinite tabletop bounds rejected")
		let safe = bounds.insetBy(dx: 24, dy: 30)
		let safeSplit = TabletopLayout.resolve(isDuo: true, bounds: safe, divisions: [fold])
		check(safeSplit?.video.minX == 24 && safeSplit?.video.minY == 30 && safeSplit?.keyboard.maxY == 690,
			  "panes stay inside supplied safe bounds")
		let camera = CGRect(x: 750, y: 0, width: 50, height: 40)
		let cameraSplit = TabletopLayout.resolve(isDuo: true, bounds: bounds, divisions: [fold], occlusions: [camera])
		check(cameraSplit != nil && cameraSplit?.video.maxX == 750, "camera occlusion excluded from upper pane")
		check(TabletopLayout.resolve(isDuo: true, bounds: bounds, divisions: [fold], occlusions: [bounds]) == nil,
			  "fully occluded panes cannot activate")

		var posture = TabletopPostureState()
		check(!posture.active, "tabletop starts inactive")
		posture.update(available: true)
		check(posture.active, "horizontal posture activates tabletop")
		posture.toggle()
		posture.update(available: true)
		check(!posture.active && posture.dismissed, "fullscreen opt-out survives fold geometry updates")
		posture.toggle()
		check(posture.active, "keyboard toggle explicitly reopens tabletop")
		posture.toggle()
		posture.update(available: false)
		check(!posture.active && !posture.dismissed, "leaving posture resets opt-out")
		posture.update(available: true)
		check(posture.active, "new tabletop posture activates again")
		posture.update(available: false)
		posture.toggle()
		check(!posture.active && !posture.dismissed, "toggle outside tabletop is inert")

		var keys = TabletopKeyState()
		func down(_ code: UInt32) -> TabletopKeyEvent { TabletopKeyEvent(code: code, pressed: true) }
		func up(_ code: UInt32) -> TabletopKeyEvent { TabletopKeyEvent(code: code, pressed: false) }
		check(keys.press(4) == [down(4)], "letter sends explicit key down")
		check(keys.press(4).isEmpty, "duplicate down ignored")
		check(keys.release(4) == [up(4)], "letter sends explicit key up")
		check(keys.release(4).isEmpty, "duplicate up ignored")
		check(keys.toggleModifier(225) == [down(225)] && keys.held.contains(225), "Shift visibly latches")
		check(keys.toggleModifier(225) == [up(225)] && !keys.held.contains(225), "Shift unlatches")
		check(keys.toggleModifier(4).isEmpty, "ordinary keys cannot latch as modifiers")
		_ = keys.press(42, repeats: true)
		_ = keys.press(80, repeats: true)
		check(keys.repeatEvents(42) == [up(42), down(42)], "backspace repeat cycles up and down")
		check(keys.repeatEvents(80) == [up(80), down(80)], "arrow repeat cycles up and down")
		_ = keys.release(42)
		check(keys.repeatEvents(42).isEmpty && !keys.repeating.contains(42), "release disables repeat")
		for modifier in TabletopKeyState.modifiers { _ = keys.toggleModifier(modifier) }
		_ = keys.press(6)
		check(keys.repeatEvents(6).isEmpty, "ordinary keys do not auto-repeat")
		let held = keys.held
		let touchGeneration = keys.generation
		let releases = keys.releaseAll()
		check(keys.generation != touchGeneration, "lifecycle reset invalidates interrupted modifier taps")
		check(Set(releases.map(\.code)) == held && releases.allSatisfy { !$0.pressed }, "lifecycle reset releases every held key")
		check(releases.first == up(6) && releases.last == up(227), "shortcut keys release before modifiers")
		check(keys.held.isEmpty && keys.repeating.isEmpty, "lifecycle reset clears modifier and repeat state")
		check(keys.repeatEvents(80).isEmpty, "late repeat callback cannot send after cancellation")
		check(keys.releaseAll().isEmpty && keys.release(80).isEmpty, "late touch-end after reset is harmless")
	}
}
