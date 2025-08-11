
import SwiftUI

struct ProfilePhotoView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photoURL = viewModel.photoURL,
               let image = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 100, height: 100)
                    .overlay(Text("S").foregroundColor(.white).font(.largeTitle))
            }

            Button(action: {
                viewModel.showPhotoPicker = true
            }) {
                Image(systemName: "camera.fill")
                    .padding(6)
                    .background(Color.white)
                    .clipShape(Circle())
            }
        }
    }
}
