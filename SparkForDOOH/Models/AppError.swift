//
//  AppError.swift
//  SparkForDOOH
//
//  Centralised error type for networking and app-level failures.
//

import Foundation

/// Unified error type used across networking (DRS, activation, polling).
enum AppError: Error, LocalizedError {
    case network(underlying: Error)
    case server(message: String)
    case decoding
    case invalidResponse
    case activationTimeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .network:
            return "Unable to reach the server. Please check the network connection and try again."
        case .server(let message):
            return message.isEmpty ? "The server reported an error. Please try again later." : message
        case .decoding:
            return "Received data in an unexpected format. Please try again later."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .activationTimeout:
            return "Activation is taking longer than expected. Please verify the code and try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }

    /// Factory to map common `Error` types into `AppError`.
    static func from(_ error: Error) -> AppError {
        if let appErr = error as? AppError {
            return appErr
        }

        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return .network(underlying: urlErr)
            default:
                return .network(underlying: urlErr)
            }
        }

        return .unknown
    }
}


