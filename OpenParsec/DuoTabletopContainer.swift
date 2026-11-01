import SwiftUI

// The content always occupies the same structural position, preserving both the
// streaming controller and its overlays as only the proposed viewport changes.
struct DuoTabletopContainer<Content: View>: View {
	@ObservedObject var session: ParsecSession
	let content: Content

	init(session: ParsecSession, @ViewBuilder content: () -> Content) {
		self.session = session
		self.content = content()
	}

	var body: some View {
		GeometryReader { geometry in
			let candidate = layout(in: geometry)
			let split = session.tabletop.active ? candidate : nil
			let video = split?.video ?? CGRect(origin: .zero, size: geometry.size)
			ZStack(alignment: .topLeading) {
				Color.black.ignoresSafeArea()
				content
					.frame(width: video.width, height: video.height)
					.position(x: video.midX, y: video.midY)
				if let split = split {
					TabletopKeyboardView(keyboard: session.controller.tabletopKeyboard)
						.frame(width: split.keyboard.width, height: split.keyboard.height)
						.position(x: split.keyboard.midX, y: split.keyboard.midY)
				}
			}
			.onAppear { session.setTabletopAvailable(candidate != nil) }
			.onChange(of: candidate) { candidate in
				session.controller.tabletopKeyboard.releaseAll()
				session.setTabletopAvailable(candidate != nil)
			}
		}
	}

	private func layout(in geometry: GeometryProxy) -> TabletopLayout? {
		#if compiler(>=6.4)
		if #available(iOS 27.1, *) {
			return TabletopLayout.resolve(
				isDuo: DuoSupport.isDuo,
				bounds: CGRect(origin: .zero, size: geometry.size),
				divisions: geometry.reservedRegions(kind: .division).map(\.frame),
				occlusions: geometry.reservedRegions(kind: .occlusion).map(\.frame)
			)
		}
		#endif
		return nil
	}
}
