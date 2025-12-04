//
//  FileManagerHelper.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 04/11/25.
//

import Foundation

final class FileManagerHelper {
    static let shared = FileManagerHelper()
    private let fileManager = FileManager.default
    
    // MARK: - Clear Files
    func clearDirectory(_ directory: FileManager.SearchPathDirectory) {
        guard let dirURL = fileManager.urls(for: directory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            for url in fileURLs {
                try fileManager.removeItem(at: url)
            }
            print("✅ Cleared files in \(directory)")
        } catch {
            print("❌ Error clearing directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Directory Size
    func directorySize(_ directory: FileManager.SearchPathDirectory) -> UInt64 {
        guard let dirURL = fileManager.urls(for: directory, in: .userDomainMask).first else { return 0 }
        var totalSize: UInt64 = 0
        
        if let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += UInt64(fileSize)
                }
            }
        }
        return totalSize
    }
    
    // MARK: - Combined Size for Documents + Caches
    func totalAppStorageSize() -> UInt64 {
        let docsSize = directorySize(.documentDirectory)
        let cacheSize = directorySize(.cachesDirectory)
        return docsSize + cacheSize
    }
    
    // MARK: - Clear Both
    func clearAppStorage() {
        print("🧹 Clearing all app storage...")
        clearDirectory(.documentDirectory)
        clearDirectory(.cachesDirectory)
        
        // Also clear temp directory
        clearTemporaryDirectory()
        
        print("✅ All app storage cleared.")
        checkFileManager()
    }
    
    // MARK: - Clear Temporary
    private func clearTemporaryDirectory() {
        let tmpURL = fileManager.temporaryDirectory
        do {
            let tmpFiles = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
            for file in tmpFiles {
                try fileManager.removeItem(at: file)
            }
            print("✅ Cleared temporary directory")
        } catch {
            print("❌ Error clearing temp: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Check All Folders
    func checkFileManager() {
        let fm = FileManager.default
        let paths = [
            ("Documents", fm.urls(for: .documentDirectory, in: .userDomainMask).first!),
            ("Caches", fm.urls(for: .cachesDirectory, in: .userDomainMask).first!),
            ("Temporary", fm.temporaryDirectory)
        ]
        
        for (name, path) in paths {
            print("🔍 Checking \(name): \(path.path)")
            var totalSize: UInt64 = 0
            
            if let files = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
                if files.isEmpty {
                    print("  ⚠️ No files here")
                } else {
                    for file in files {
                        do {
                            let attributes = try fm.attributesOfItem(atPath: file.path)
                            let fileSize = attributes[.size] as? UInt64 ?? 0
                            totalSize += fileSize
                            
                            let sizeKB = Double(fileSize) / 1024.0
                            let sizeString = sizeKB > 1024 ? String(format: "%.2f MB", sizeKB / 1024.0)
                                                           : String(format: "%.2f KB", sizeKB)
                            print("  📄 \(file.lastPathComponent) — \(sizeString)")
                            
                        } catch {
                            print("  ❌ Error reading \(file.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            let totalMB = Double(totalSize) / (1024.0 * 1024.0)
            print("📦 Total \(name) folder size: \(String(format: "%.2f MB", totalMB))\n")
        }
    }
}
