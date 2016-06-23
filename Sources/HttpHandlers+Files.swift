//
//  HttpHandlers+Files.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

extension HttpHandlers {
    
    public class func shareFilesFromDirectory(_ directoryPath: String) -> ((HttpRequest) -> HttpResponse) {
        return { r in
            guard let absolutePath = self.fileNameToShare(directoryPath, request: r) else {
                return .notFound
            }

            guard let file = try? File.openForReading(absolutePath) else {
                return .notFound
            }
            return .raw(200, "OK", [:], { writer in
                var buffer = [UInt8](repeating: 0, count: 64)
                while let count = try? file.read(&buffer) where count > 0 {
                    writer.write(buffer[0 ..< count])
                }
                file.close()
            })
        }
    }

    private class func fileNameToShare(_ directoryPath: String, request: HttpRequest) -> String? {
        let path = request.path
        let fileRelativePath = request.params.first

        if !path.hasSuffix("/"), let fileRelativePath = fileRelativePath {
            let absolutePath = directoryPath + "/" + fileRelativePath.1
            return absolutePath
        }

        let fm = FileManager.default()
        let possibleIndexFiles = ["index.html", "index.htm"] // add any other files you want to check for here
        var folderPath = directoryPath
        if let fileRelativePath = fileRelativePath {
            folderPath += "/\(fileRelativePath.1)"
        }

        for indexFile in possibleIndexFiles {
            let indexPath = "\(folderPath)/\(indexFile)"
            if fm.fileExists(atPath: indexPath) {
                return indexPath
            }
        }
        
        return nil
    }

    private static let rangePrefix = "bytes="
    
    public class func directory(_ dir: String) -> ((HttpRequest) -> HttpResponse) {
        return { r in
            
            guard let localPath = r.params.first else {
                return HttpResponse.notFound
            }
            
            let filesPath = dir + "/" + localPath.1
            
            guard let fileBody = try? Data(contentsOf: URL(fileURLWithPath: filesPath)) else {
                return HttpResponse.notFound
            }
            
            if let rangeHeader = r.headers["range"] {
                
                guard rangeHeader.hasPrefix(HttpHandlers.rangePrefix) else {
                    return .badRequest(.text("Invalid value of 'Range' header: \(r.headers["range"])"))
                }
                
                #if os(Linux)
                    let rangeString = rangeHeader.substringFromIndex(HttpHandlers.rangePrefix.characters.count)
                #else
                    let rangeString = rangeHeader.substring(from: rangeHeader.characters.index(rangeHeader.startIndex, offsetBy: HttpHandlers.rangePrefix.characters.count))
                #endif
                
                let rangeStringExploded = rangeString.split("-")
                
                guard rangeStringExploded.count == 2 else {
                    return .badRequest(.text("Invalid value of 'Range' header: \(r.headers["range"])"))
                }
                
                let startStr = rangeStringExploded[0]
                let endStr   = rangeStringExploded[1]
                
                guard let start = Int(startStr), end = Int(endStr) else {
                    var array = [UInt8](repeating: 0, count: fileBody.count)
                    (fileBody as NSData).getBytes(&array, length: fileBody.count)
                    return HttpResponse.raw(200, "OK", nil, { $0.write(array) })
                }
                
                let chunkLength = end - start
                let chunkRange = Range<Int>.init(uncheckedBounds: (lower: start, upper: start + chunkLength + 1))
                
                guard chunkRange.upperBound <= fileBody.count else {
                    return HttpResponse.raw(416, "Requested range not satisfiable", nil, nil)
                }
                
                let chunk = fileBody.subdata(in: chunkRange)
                
                let headers = [ "Content-Range" : "bytes \(startStr)-\(endStr)/\(fileBody.count)" ]
                
                var content = [UInt8](repeating: 0, count: chunk.count)
                (chunk as NSData).getBytes(&content, length: chunk.count)
                return HttpResponse.raw(206, "Partial Content", headers, { $0.write(content) })
            } else {
                var content = [UInt8](repeating: 0, count: fileBody.count)
                (fileBody as NSData).getBytes(&content, length: fileBody.count)
                return HttpResponse.raw(200, "OK", nil, { $0.write(content) })
            }
        }
    }
    
    public class func directoryBrowser(_ dir: String) -> ((HttpRequest) -> HttpResponse) {
        return { r in
            guard let (_, value) = r.params.first else {
                return HttpResponse.notFound
            }
            let filePath = dir + "/" + value
            let fileManager = FileManager.default()
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: filePath, isDirectory: &isDir) else {
                return HttpResponse.notFound
            }
            if isDir {
                do {
                    let files = try fileManager.contentsOfDirectory(atPath: filePath)
                    var response = "<h3>\(filePath)</h3></br><table>"
                    response += files.map({ "<tr><td><a href=\"\(r.path)/\($0)\">\($0)</a></td></tr>"}).joined(separator: "")
                    response += "</table>"
                    return HttpResponse.ok(.html(response))
                } catch {
                    return HttpResponse.notFound
                }
            } else {
                if let content = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                    var array = [UInt8](repeating: 0, count: content.count)
                    (content as NSData).getBytes(&array, length: content.count)
                    return HttpResponse.raw(200, "OK", nil, { $0.write(array) })
                }
                return HttpResponse.notFound
            }
        }
    }
}
