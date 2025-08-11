
import SwiftUI
struct ChronicAlertSheet: View {
    @ObservedObject var viewModel: PhysicalDataViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Хронические заболевания")
                .font(.title2).bold()
                .foregroundColor(.white)
                .padding(.top)
            
            Text("Хронические заболевания, которые не позволяют или сильно усложняют выполнение тренировочного плана. Если такие имеются, то есть вероятность что вам нужно будет делать тренировки в соответствии с вашими собственными возможностями, вне соответствия с планом.")
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                viewModel.showChronicAlert = false
                viewModel.showChronicTextField = true
            }) {
                Text("Понятно")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents([.fraction(0.5)])
        .background(Color.black)
    }
}
