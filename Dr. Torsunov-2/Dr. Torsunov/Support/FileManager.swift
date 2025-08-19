import Foundation
extension FileManager {
    func saveToDocuments(data: Data, filename: String) -> URL? {
        let url = urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("❌ Failed to save image: \(error)")
            return nil
        }
    }
}
