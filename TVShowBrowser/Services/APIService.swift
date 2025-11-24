//
//  APIService.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation

final class APIService {
    static let shared = APIService()
    private init() {}

    func fetchItemSeqInfo(screenId: String, reqNum: Int, completion: @escaping (Result<ItemSeqInfoResponse, Error>) -> Void) {
        guard let url = URL(string: "https://qa-drs-service.doceree.com/drs/v2/quest") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["screenid": screenId, "reqNum": reqNum]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "No data returned", code: 0)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ItemSeqInfoResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                print("❌ Decoding error: \(error)")
                if let raw = String(data: data, encoding: .utf8) {
                    print("Raw JSON:\n\(raw)")
                }
                completion(.failure(error))
            }
        }.resume()
    }
}
