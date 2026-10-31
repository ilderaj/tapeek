import AppKit
import QuickLookUI
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSView?

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        hostingView?.removeFromSuperview()

        let host = NSHostingView(
            rootView: Text("TAPEEK-SMOKE")
                .font(.system(size: 32, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
        )
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        hostingView = host
        handler(nil)
    }
}
