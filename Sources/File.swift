//
//  File.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

public enum FileError: ErrorProtocol {
    case openFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case seekFailed(String)
    case getCurrentWorkingDirectoryFailed(String)
}

public class File {
    
    public static func openNewForWriting(_ path: String) throws -> File {
        return try openFileForMode(path, "wb")
    }
    
    public static func openForReading(_ path: String) throws -> File {
        return try openFileForMode(path, "rb")
    }
    
    public static func openForWritingAndReading(_ path: String) throws -> File {
        return try openFileForMode(path, "r+b")
    }
    
    public static func openFileForMode(_ path: String, _ mode: String) throws -> File {
        let file = fopen(path.withCString({ $0 }), mode.withCString({ $0 }))
        guard file != nil else {
            throw FileError.openFailed(descriptionOfLastError())
        }
        return File(file!)
    }
    
    public static func currentWorkingDirectory() throws -> String {
        let path = getcwd(nil, 0)
        if path == nil {
            throw FileError.getCurrentWorkingDirectoryFailed(descriptionOfLastError())
        }
        guard let result = String(validatingUTF8: path!) else {
            throw FileError.getCurrentWorkingDirectoryFailed("Could not convert getcwd(...)'s result to String.")
        }
        return result
    }
    
    private let pointer: UnsafeMutablePointer<FILE>
    
    public init(_ pointer: UnsafeMutablePointer<FILE>) {
        self.pointer = pointer
    }
    
    public func close() -> Void {
        fclose(pointer)
    }
    
    public func read(_ data: inout [UInt8]) throws -> Int {
        if data.count <= 0 {
            return data.count
        }
        let count = fread(&data, 1, data.count, self.pointer)
        if count == data.count {
            return count
        }
        if feof(self.pointer) != 0 {
            return count
        }
        if ferror(self.pointer) != 0 {
            throw FileError.readFailed(File.descriptionOfLastError())
        }
        throw FileError.readFailed("Unknown file read error occured.")
    }

    public func write(_ data: [UInt8]) throws -> Void {
        if data.count <= 0 {
            return
        }
        try data.withUnsafeBufferPointer {
            if fwrite($0.baseAddress, 1, data.count, self.pointer) != data.count {
                throw FileError.writeFailed(File.descriptionOfLastError())
            }
        }
    }
    
    public func seek(_ offset: Int) throws -> Void {
        if fseek(self.pointer, offset, SEEK_SET) != 0 {
            throw FileError.seekFailed(File.descriptionOfLastError())
        }
    }
    
    private static func descriptionOfLastError() -> String {
        return String(cString: UnsafePointer(strerror(errno))) ?? "Error: \(errno)"
    }
}

extension File {
    
    public static func withNewFileOpenedForWriting<Result>(_ path: String, _ f: (File) throws -> Result) throws -> Result {
        return try withFileOpenedForMode(path, mode: "wb", f)
    }
    
    public static func withFileOpenedForReading<Result>(_ path: String, _ f: (File) throws -> Result) throws -> Result {
        return try withFileOpenedForMode(path, mode: "rb", f)
    }
    
    public static func withFileOpenedForWritingAndReading<Result>(_ path: String, _ f: (File) throws -> Result) throws -> Result {
        return try withFileOpenedForMode(path, mode: "r+b", f)
    }
    
    public static func withFileOpenedForMode<Result>(_ path: String, mode: String, _ f: (File) throws -> Result) throws -> Result {
        let file = try File.openFileForMode(path, mode)
        defer {
            file.close()
        }
        return try f(file)
    }
}
