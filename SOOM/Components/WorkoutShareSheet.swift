import SwiftUI
import UIKit

struct WorkoutShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        makeActivityViewController()
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    func makeActivityViewController() -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
}
