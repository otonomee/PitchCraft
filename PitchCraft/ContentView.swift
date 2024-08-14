import SwiftUI
import AVFoundation
import Accelerate

class AudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var pitchNode: AVAudioUnitTimePitch!
    private var audioFile: AVAudioFile?
    @Published var audioBuffer: AVAudioPCMBuffer?
    
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        pitchNode = AVAudioUnitTimePitch()
        
        audioEngine.attach(playerNode)
        audioEngine.attach(pitchNode)
        
        audioEngine.connect(playerNode, to: pitchNode, format: nil)
        audioEngine.connect(pitchNode, to: audioEngine.mainMixerNode, format: nil)
        
        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    func loadAudio(url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let audioFormat = audioFile?.processingFormat else { return }
            guard let audioFrameCount = audioFile?.length else { return }
            
            audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(audioFrameCount))
            try audioFile?.read(into: audioBuffer!)
            
            duration = Double(audioFrameCount) / audioFormat.sampleRate
        } catch {
            print("Error loading audio file: \(error)")
        }
    }
    
    func play() {
        guard let audioBuffer = audioBuffer else { return }
        playerNode.scheduleBuffer(audioBuffer, at: nil, options: .loops, completionHandler: nil)
        playerNode.play()
        isPlaying = true
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
    }
    
    func seek(to time: Double) {
        guard let audioBuffer = audioBuffer else { return }
        let wasPlaying = isPlaying
        stop()
        
        let sampleRate = audioBuffer.format.sampleRate
        let frameCount = AVAudioFrameCount(time * sampleRate)
        
        playerNode.scheduleBuffer(audioBuffer, at: nil, options: [], startingFrame: frameCount)
        
        if wasPlaying {
            play()
        }
        currentTime = time
    }
    
    func setPitch(_ pitch: Float) {
        pitchNode.pitch = 1200 * log2(pitch)
    }
}

struct WaveformView: View {
    let audioBuffer: AVAudioPCMBuffer?
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard let audioBuffer = audioBuffer else { return }
                let channelData = audioBuffer.floatChannelData![0]
                let frameLength = Int(audioBuffer.frameLength)
                let stride = max(1, frameLength / Int(geometry.size.width))
                
                var x: CGFloat = 0
                var y: CGFloat = geometry.size.height / 2
                
                path.move(to: CGPoint(x: x, y: y))
                
                for i in stride(from: 0, to: frameLength, by: stride) {
                    let sample = CGFloat(channelData[i])
                    y = geometry.size.height / 2 + sample * geometry.size.height / 2
                    x += 1
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.blue, lineWidth: 1)
        }
    }
}


struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var pitch: Float = 1.0
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack {
            Button("Import Audio") {
                showingFilePicker = true
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let url) = result {
                    audioManager.loadAudio(url: url[0])
                }
            }
            
            if audioManager.duration > 0 {
                WaveformView(audioBuffer: audioManager.audioBuffer)
                    .frame(height: 100)
                
                Slider(value: $audioManager.currentTime, in: 0...audioManager.duration) { _ in
                    audioManager.seek(to: audioManager.currentTime)
                }
                
                Text("Pitch: \(pitch, specifier: "%.2f")")
                Slider(value: $pitch, in: 0.5...2.0, step: 0.01) { _ in
                    audioManager.setPitch(pitch)
                }
                
                Button(audioManager.isPlaying ? "Stop" : "Play") {
                    if audioManager.isPlaying {
                        audioManager.stop()
                    } else {
                        audioManager.play()
                    }
                }
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
