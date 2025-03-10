/* import SwiftUI
@available(macOS 15.0, *)
public struct FolderDiscoveryProgressView: View {
    @ObservedObject var viewModel: FolderDiscoveryViewModel
    
    public var body: some View {
        VStack(spacing: 16) {
            if let progress = viewModel.progress {
                ProgressView(value: Double(progress.processedVideos), total: Double(progress.totalVideos)) {
                    HStack {
                        Text("Processing Videos")
                        Spacer()
                        Text("\(progress.processedVideos)/\(progress.totalVideos)")
                    }
                }
                
                if !progress.currentVideo.isEmpty {
                    Text("Current: \(progress.currentVideo)")
                        .foregroundStyle(.secondary)
                }
                
                if let timeRemaining = progress.estimatedTimeRemaining {
                    Text("Estimated time remaining: \(formatTimeRemaining(timeRemaining))")
                        .foregroundStyle(.secondary)
                }
                
                if progress.errorFiles > 0 {
                    Text("Errors: \(progress.errorFiles)")
                        .foregroundStyle(.red)
                }
            } else {
                ProgressView()
                Text("Preparing...")
                    .foregroundStyle(.secondary)
            }
            
            if let error = viewModel.lastError {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
            }
            
            Button("Cancel") {
                viewModel.cancel()
            }
            .disabled(!viewModel.isDiscovering)
        }
        .padding()
        .frame(width: 300)
    }
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: timeInterval) ?? ""
    }
}
@available(macOS 15.0, *)
#Preview {
    FolderDiscoveryProgressView(viewModel: FolderDiscoveryViewModel(discoveryService: FolderDiscoveryService(
        videoFinder: VideoFinderService(),
        videoProcessor: VideoProcessor()
    )))
} */