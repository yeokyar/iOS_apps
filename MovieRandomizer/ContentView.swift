import SwiftUI

// --- DATA MODELS ---
struct MovieResponse: Codable {
    let results: [Movie]
}

struct Movie: Codable {
    let title: String
}

// --- MAIN ROUTER ---
struct ContentView: View {
    @AppStorage("hasCompletedSetup") var hasCompletedSetup = false
    
    var body: some View {
        if hasCompletedSetup {
            RandomizerView()
        } else {
            OnboardingView()
        }
    }
}

// --- SETUP SCREEN ---
struct OnboardingView: View {
    @AppStorage("hasCompletedSetup") var hasCompletedSetup = false
    @AppStorage("selectedRegion") var selectedRegion = "TR"
    @AppStorage("preferredLanguage") var preferredLanguage = "any"
    
    let regions = ["TR", "US", "GB", "DE", "FR"]
    let languages = ["Any": "any", "Turkish": "tr", "English": "en", "German": "de", "French": "fr"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Picker("Watch Region", selection: $selectedRegion) {
                        ForEach(regions, id: \.self) { Text($0) }
                    }
                    Picker("Movie Language", selection: $preferredLanguage) {
                        ForEach(languages.keys.sorted(), id: \.self) { key in
                            Text(key).tag(languages[key] ?? "any")
                        }
                    }
                }
                Button("Start Randomizing") {
                    withAnimation { hasCompletedSetup = true }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("App Setup")
        }
    }
}

// --- THE HAPTIC RANDOMIZER ---
struct RandomizerView: View {
    @AppStorage("hasCompletedSetup") var hasCompletedSetup = false
    @AppStorage("selectedRegion") var selectedRegion = "TR"
    @AppStorage("preferredLanguage") var preferredLanguage = "any"
    
    @State private var isPressing = false
    @State private var selectedMovie: String? = nil
    @State private var seenMovieTitles: Set<String> = []
    @State private var isLoading = false
    @State private var startTime: Date?
    
    // --- LIGHT & SHADOW STATES ---
    @State private var fingerLocation: CGPoint = .zero
    @State private var shadowOffset: CGSize = CGSize(width: 10, height: 10)
    
    let apiKey = "f6b14959b0476e78f396d2613047a414"

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.05, blue: 0.2).ignoresSafeArea()
            
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Region: \(selectedRegion)")
                        Text("Lang: \(preferredLanguage.uppercased())")
                    }
                    .foregroundColor(.white.opacity(0.3))
                    .font(.caption2)
                    Spacer()
                    Button("Reset Setup") { hasCompletedSetup = false }
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding()

                Spacer()
                
                // --- THE INTERACTIVE LIGHT BUTTON ---
                ZStack {
                    // This circle acts as the "Shadow Layer"
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 210, height: 210)
                        .blur(radius: isPressing ? 5 : 15)
                        // The shadow moves OPPOSITE to the finger
                        .offset(shadowOffset)
                    
                    // The "Button Layer"
                    Circle()
                        .fill(
                            // The gradient startPoint follows the finger
                            LinearGradient(
                                stops: [
                                    .init(color: .orange, location: 0),
                                    .init(color: .pink, location: 1)
                                ],
                                startPoint: UnitPoint(
                                    x: 0.5 + (shadowOffset.width / -100),
                                    y: 0.5 + (shadowOffset.height / -100)
                                ),
                                endPoint: .center
                            )
                        )
                        .frame(width: 220, height: 220)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(isPressing ? 0.94 : 1.0)
                    
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(2)
                    } else {
                        Text("TAP")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isPressing {
                                isPressing = true
                                startTime = Date()
                            }
                            
                            // Calculate how far the finger is from the center (approx center of screen)
                            // We use -1/10th of the distance to keep the shadow movements subtle
                            let dx = (value.location.x - (UIScreen.main.bounds.width / 2)) / 10
                            let dy = (value.location.y - (UIScreen.main.bounds.height / 2)) / 10
                            
                            withAnimation(.interactiveSpring()) {
                                // Shadow moves away from the finger
                                shadowOffset = CGSize(width: -dx, height: -dy)
                            }
                        }
                        .onEnded { _ in
                            isPressing = false
                            handleRelease()
                            // Reset shadow to center-ish
                            withAnimation(.spring()) {
                                shadowOffset = CGSize(width: 5, height: 10)
                            }
                        }
                )

                if let movie = selectedMovie {
                    Text(movie)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
            }
        }
    }

    func handleRelease() {
        guard let start = startTime else { return }
        let duration = Date().timeIntervalSince(start)
        
        if duration < 0.2 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if duration < 0.6 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        
        selectedMovie = nil
        fetchRandomMovie()
    }

    func fetchRandomMovie() {
        isLoading = true
        let uiLang = selectedRegion == "TR" ? "tr-TR" : "en-US"
        let langFilter = preferredLanguage == "any" ? "" : "&with_original_language=\(preferredLanguage)"
        let randomPage = Int.random(in: 1...100)
        let urlString = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=\(uiLang)&watch_region=\(selectedRegion)\(langFilter)&sort_by=popularity.desc&page=\(randomPage)"
        
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let decoded = try? JSONDecoder().decode(MovieResponse.self, from: data) {
                    let freshMovies = decoded.results.filter { !seenMovieTitles.contains($0.title) }
                    if let selection = freshMovies.randomElement() {
                        withAnimation(.spring()) {
                            self.selectedMovie = selection.title
                            self.seenMovieTitles.insert(selection.title)
                        }
                    }
                }
                self.isLoading = false
            }
        }.resume()
    }
}
