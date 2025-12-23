//
//  WeatherService.swift
//  SparkForDOOH
//
//  Fetches current weather data for display on the DOOH screen.
//

import Foundation
import CoreLocation

/// Weather data model
struct WeatherData {
    let temperature: Int  // in Celsius
    let condition: WeatherCondition
    
    enum WeatherCondition: String {
        case sunny = "sun.max.fill"
        case cloudy = "cloud.fill"
        case partlyCloudy = "cloud.sun.fill"
        case rainy = "cloud.rain.fill"
        case stormy = "cloud.bolt.rain.fill"
        case snowy = "cloud.snow.fill"
        case foggy = "cloud.fog.fill"
        case unknown = "questionmark.circle"
        
        var iconName: String { rawValue }
    }
}

/// Service to fetch weather data using OpenWeatherMap API (or mock data)
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    
    @Published var currentWeather: WeatherData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // OpenWeatherMap API key (can be configured via AppConfig)
    private let apiKey: String
    
    // Default location (can be updated based on device location or config)
    private var latitude: Double = 28.6139  // Delhi, India (default)
    private var longitude: Double = 77.2090
    
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 30 * 60  // 30 minutes
    
    private init() {
        // API key can be configured in AppConfig or use a default
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "WEATHER_API_KEY") as? String ?? ""
    }
    
    /// Start fetching weather and refreshing periodically
    func startWeatherUpdates() {
        fetchWeather()
        
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchWeather()
            }
        }
    }
    
    func stopWeatherUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Fetch current weather
    func fetchWeather() {
        // If no API key, use mock data
        if apiKey.isEmpty {
            useMockWeather()
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let weather = try await fetchFromAPI()
                self.currentWeather = weather
                self.errorMessage = nil
            } catch {
                print("⚠️ Weather fetch failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                // Fall back to mock data
                useMockWeather()
            }
            self.isLoading = false
        }
    }
    
    /// Update location for weather
    func updateLocation(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        fetchWeather()
    }
    
    // MARK: - Private Methods
    
    private func fetchFromAPI() async throws -> WeatherData {
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=metric"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
        
        let condition = mapCondition(from: response.weather.first?.main ?? "")
        return WeatherData(temperature: Int(response.main.temp), condition: condition)
    }
    
    private func mapCondition(from description: String) -> WeatherData.WeatherCondition {
        let lower = description.lowercased()
        if lower.contains("clear") || lower.contains("sun") {
            return .sunny
        } else if lower.contains("cloud") {
            return .cloudy
        } else if lower.contains("rain") || lower.contains("drizzle") {
            return .rainy
        } else if lower.contains("thunder") || lower.contains("storm") {
            return .stormy
        } else if lower.contains("snow") {
            return .snowy
        } else if lower.contains("fog") || lower.contains("mist") || lower.contains("haze") {
            return .foggy
        }
        return .partlyCloudy
    }
    
    private func useMockWeather() {
        // Use realistic mock data based on time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let temp: Int
        let condition: WeatherData.WeatherCondition
        
        // Simulate temperature variation
        if hour >= 6 && hour < 12 {
            temp = Int.random(in: 18...24)
            condition = .sunny
        } else if hour >= 12 && hour < 17 {
            temp = Int.random(in: 24...32)
            condition = .sunny
        } else if hour >= 17 && hour < 20 {
            temp = Int.random(in: 20...26)
            condition = .partlyCloudy
        } else {
            temp = Int.random(in: 16...22)
            condition = .cloudy
        }
        
        currentWeather = WeatherData(temperature: temp, condition: condition)
        print("🌤️ Using mock weather: \(temp)°C, \(condition)")
    }
}

// MARK: - OpenWeatherMap API Response Models

private struct OpenWeatherResponse: Codable {
    let main: MainWeather
    let weather: [WeatherDescription]
}

private struct MainWeather: Codable {
    let temp: Double
    let humidity: Int
}

private struct WeatherDescription: Codable {
    let main: String
    let description: String
}

