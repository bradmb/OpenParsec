import Foundation
import CoreGraphics

struct TabletopLayout: Equatable {
	let video: CGRect
	let keyboard: CGRect

	// The caller supplies only active divisions, in the outer container's coordinates.
	// Reserved-region frames already include the system's fold margins.
	static func resolve(isDuo: Bool, bounds: CGRect, divisions: [CGRect], occlusions: [CGRect] = []) -> Self? {
		guard isDuo, valid(bounds) else { return nil }
		for fold in divisions where valid(fold) && fold.width > fold.height {
			guard fold.minX <= bounds.minX + 1, fold.maxX >= bounds.maxX - 1,
				  fold.minY > bounds.minY, fold.maxY < bounds.maxY else { continue }
			let upper = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fold.minY - bounds.minY)
			let lower = CGRect(x: bounds.minX, y: fold.maxY, width: bounds.width, height: bounds.maxY - fold.maxY)
			let video = AdaptiveGeometry.controlRegion(in: upper, avoiding: occlusions)
			let keyboard = AdaptiveGeometry.controlRegion(in: lower, avoiding: occlusions)
			guard video.width >= 240, video.height >= 120, keyboard.width >= 240, keyboard.height >= 120,
				  !occlusions.contains(where: { overlaps(video, $0) || overlaps(keyboard, $0) }) else { continue }
			return Self(video: video, keyboard: keyboard)
		}
		return nil
	}

	private static func valid(_ rect: CGRect) -> Bool {
		rect.origin.x.isFinite && rect.origin.y.isFinite && AdaptiveGeometry.valid(rect.size)
	}

	private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
		let intersection = a.intersection(b)
		return !intersection.isNull && intersection.width > 0 && intersection.height > 0
	}
}

struct TabletopPostureState {
	private(set) var available = false
	private(set) var dismissed = false
	var active: Bool { available && !dismissed }

	mutating func update(available: Bool) {
		self.available = available
		if !available { dismissed = false }
	}

	mutating func toggle() {
		guard available else { return }
		dismissed.toggle()
	}
}

struct TabletopKeyEvent: Equatable {
	let code: UInt32
	let pressed: Bool
}

// USB HID codes, shared with the physical keyboard's Parsec event path.
struct TabletopKeyState {
	private(set) var held: Set<UInt32> = []
	private(set) var repeating: Set<UInt32> = []
	private(set) var generation: UInt = 0
	static let modifiers: Set<UInt32> = [224, 225, 226, 227]

	mutating func press(_ code: UInt32, repeats: Bool = false) -> [TabletopKeyEvent] {
		guard held.insert(code).inserted else { return [] }
		if repeats { repeating.insert(code) }
		return [TabletopKeyEvent(code: code, pressed: true)]
	}

	mutating func release(_ code: UInt32) -> [TabletopKeyEvent] {
		repeating.remove(code)
		guard held.remove(code) != nil else { return [] }
		return [TabletopKeyEvent(code: code, pressed: false)]
	}

	mutating func toggleModifier(_ code: UInt32) -> [TabletopKeyEvent] {
		guard Self.modifiers.contains(code) else { return [] }
		return held.contains(code) ? release(code) : press(code)
	}

	func repeatEvents(_ code: UInt32) -> [TabletopKeyEvent] {
		guard held.contains(code), repeating.contains(code) else { return [] }
		return [TabletopKeyEvent(code: code, pressed: false), TabletopKeyEvent(code: code, pressed: true)]
	}

	mutating func releaseAll() -> [TabletopKeyEvent] {
		generation &+= 1
		// Release ordinary keys before modifiers so a held shortcut completes cleanly.
		let codes = held.sorted {
			let left = Self.modifiers.contains($0), right = Self.modifiers.contains($1)
			return left == right ? $0 < $1 : !left
		}
		held.removeAll()
		repeating.removeAll()
		return codes.map { TabletopKeyEvent(code: $0, pressed: false) }
	}
}
