import SwiftUI

struct FoodEvidenceCameraView: UIViewControllerRepresentable {
    var captureAction: (Data) -> Void
    var cancelAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(captureAction: captureAction, cancelAction: cancelAction)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let captureAction: (Data) -> Void
        let cancelAction: () -> Void

        init(captureAction: @escaping (Data) -> Void, cancelAction: @escaping () -> Void) {
            self.captureAction = captureAction
            self.cancelAction = cancelAction
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            cancelAction()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.95) else {
                cancelAction()
                return
            }
            captureAction(data)
        }
    }
}
