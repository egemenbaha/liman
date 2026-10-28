import Foundation
import UniformTypeIdentifiers

public enum WebMediaKind:String,Codable,Sendable { case image,video,audio }
public enum WebDownloadMode:String,CaseIterable,Sendable { case original,video,audioMP3
    public var title:String { switch self { case .original:return "Original file";case .video:return "Video";case .audioMP3:return "Audio · MP3" } }
}
public struct WebMediaInfo:Sendable {
    public let url:URL
    public let title:String
    public let kind:WebMediaKind
    public let site:String
    public let duration:Double?
    public let heights:[Int]
    public let direct:Bool
    public let filename:String?
    public let byteCount:Int64?
    public var imageWidth:Int? = nil
    public var imageHeight:Int? = nil
    public var photos:[WebPhoto] = []
    public var skippedVideoCount:Int = 0
    public var modes:[WebDownloadMode] { kind == .image ? [.original]:direct || kind == .audio ? [.original,.audioMP3]:[.video,.audioMP3] }
}

public enum WebDownloadEngine {
    public static func link(_ text:String) throws -> URL {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.utf8.count<=16_384,!value.unicodeScalars.contains(where:{CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)}),
              let url=URL(string:value),let scheme=url.scheme?.lowercased(),["http","https"].contains(scheme),
              let host=url.host,!host.isEmpty,url.user==nil,url.password==nil else {
            throw NashiError.invalidInput("Paste one complete http:// or https:// media link.")
        }
        _ = try PublicWebPolicy.validate(url)
        return url
    }
    public static func inspect(_ url:URL,token:CancellationToken = .init()) async throws -> WebMediaInfo {
        let url=try link(url.absoluteString);try token.check()
        let staging = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        // Preflight external extractors too, but their own subsequent requests
        // still need an OS-enforced egress boundary (tracked in SECURITY-AUDIT).
        _ = try await Task.detached { try PublicWebPolicy.pinnedAddress(for: url) }.value
        if WebMediaDragPayload.isInstagramPhotoPost(url) {
            let args=try baseArguments(photoPost:true)+["--ignore-no-formats-error","--skip-download","--dump-single-json","--no-progress","--",url.absoluteString]
            let data=try await Task.detached { try WebDownloadProcess.run(Dependencies.executable("yt-dlp"),args,token:token,timeout:100) }.value
            try token.check();try Task.checkCancellation()
            return try InstagramPhotos.parse(data,url:url)
        }
        if let cover=try await YouTubeThumbnail.resolve(url,token:token,fetch:{ candidate in
            let file = staging.appendingPathComponent("thumbnail")
            let response = try await PublicWebTransfer.fetchAsync(candidate, to: file, maximumBytes: 20 * 1024 * 1024, token: token)
            guard (200...299).contains(response.statusCode),
                  response.mimeType?.lowercased().hasPrefix("image/")==true else { return nil }
            return try Data(contentsOf: file)
        }) {
            return WebMediaInfo(url:cover.url,title:"YouTube thumbnail",kind:.image,site:"YouTube",duration:nil,heights:[],direct:true,
                                filename:cover.url.lastPathComponent,byteCount:Int64(cover.byteCount),imageWidth:cover.width,imageHeight:cover.height)
        }
        // Security/transport failures must not fall through to an unpinned extractor.
        let response = try await PublicWebTransfer.fetchAsync(url, to: staging.appendingPathComponent("head"), head: true, maximumBytes: 0, token: token)
        if (200...299).contains(response.statusCode),
           let kind=directKind(mime:response.mimeType,extension:url.pathExtension) {
            try token.check();try Task.checkCancellation()
            return WebMediaInfo(url:url,title:cleanFilename(response.suggestedFilename ?? url.lastPathComponent,mime:response.mimeType),kind:kind,site:url.host ?? "Web",duration:nil,heights:[],direct:true,filename:response.suggestedFilename,byteCount:response.expectedContentLength>0 ? response.expectedContentLength:nil)
        }
        try Task.checkCancellation();try token.check()
        let args=try baseArguments()+["--skip-download","--dump-single-json","--no-progress","--",url.absoluteString]
        let data=try await Task.detached { try WebDownloadProcess.run(Dependencies.executable("yt-dlp"),args,token:token,timeout:100) }.value
        try Task.checkCancellation();try token.check()
        return try parseMetadata(data,url:url)
    }

    /// Fetch a bounded image preview through the same network boundary as downloads.
    public static func preview(_ url: URL) async throws -> Data {
        let staging = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        let file = staging.appendingPathComponent("preview")
        let response = try await PublicWebTransfer.fetchAsync(url, to: file, maximumBytes: 8 * 1024 * 1024, token: .init())
        guard (200...299).contains(response.statusCode), response.mimeType?.hasPrefix("image/") == true else {
            throw NashiError.failed("The preview is not a public image.")
        }
        return try Data(contentsOf: file)
    }

    public static func parseMetadata(_ data:Data,url:URL) throws -> WebMediaInfo {
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw NashiError.failed("The site did not return readable media details.") }
        let item=(root["entries"] as? [[String:Any]])?.first ?? root
        if item["is_live"] as? Bool==true || ["is_live","is_upcoming"].contains(item["live_status"] as? String ?? "") { throw NashiError.unsupported("This is a live or upcoming stream. Use a finished video link.") }
        let rawFormats=item["formats"] as? [[String:Any]] ?? []
        let formats=rawFormats.filter{$0["has_drm"] as? Bool != true}
        guard item["has_drm"] as? Bool != true,(rawFormats.isEmpty || !formats.isEmpty),!formats.isEmpty || item["url"] as? String != nil else { throw NashiError.unsupported("No downloadable public media was found. Login-required and protected media are not supported.") }
        let heights=Array(Set(formats.compactMap{$0["height"] as? Int}.filter{$0>0 && $0<=16_384})).sorted()
        let audioExtensions=["mp3","m4a","wav","flac","ogg","opus","aac","aiff"]
        let audioOnly=item["vcodec"] as? String == "none" || (!formats.isEmpty && formats.allSatisfy { $0["vcodec"] as? String == "none" || audioExtensions.contains($0["ext"] as? String ?? "") })
        // Generic HTML5 videos often omit both height and codec metadata.
        let video = !heights.isEmpty || !audioOnly
        let duration=(item["duration"] as? Double).flatMap{$0.isFinite && $0>0 && $0<31_536_000 ? $0:nil}
        return WebMediaInfo(url:url,title:String((item["title"] as? String ?? "Web media").prefix(300)),kind:video ? .video:.audio,site:item["extractor_key"] as? String ?? url.host ?? "Web",duration:duration,heights:heights,direct:false,filename:nil,byteCount:nil)
    }

    public static func download(_ info:WebMediaInfo,mode:WebDownloadMode,maximumHeight:Int?,destination:URL,selectedPhotos:Set<Int>? = nil,
                                token:CancellationToken = .init(),progress:@escaping ProgressHandler) async throws -> [URL] {
        _=try link(info.url.absoluteString)
        guard destination.isFileURL,info.modes.contains(mode) else { throw NashiError.invalidInput("Choose an available media type and a local destination folder.") }
        if let maximumHeight { guard (2...16_384).contains(maximumHeight) else { throw NashiError.invalidInput("Choose a valid video quality.") } }
        try token.check();try Task.checkCancellation()
        let transaction=ExportTransaction();let area=try transaction.makeArea(destination:destination)
        defer { transaction.cleanUp() }
        let results:[URL]
        if !info.photos.isEmpty {
            results=try await InstagramPhotos.download(info,selected:selectedPhotos,directory:area.directory,token:token,progress:progress)
        } else if info.direct {
            results=try await downloadDirect(info,mode:mode,directory:area.directory,token:token,progress:progress)
        } else {
            _ = try await Task.detached { try PublicWebPolicy.pinnedAddress(for: info.url) }.value
            let arguments=try downloadArguments(info,mode:mode,maximumHeight:maximumHeight,directory:area.directory)
            let data=try await Task.detached { try WebDownloadProcess.run(Dependencies.executable("yt-dlp"),arguments,token:token,timeout:21_600,progress:progress) }.value
            results=String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap { line in
                guard line.hasPrefix("NASHI_FILE:"),let encoded=String(line.dropFirst("NASHI_FILE:".count)).data(using:.utf8),
                      let path=(try? JSONSerialization.jsonObject(with:encoded,options:.fragmentsAllowed)) as? String else { return nil }
                return URL(fileURLWithPath:path)
            }
        }
        try Task.checkCancellation();try token.check()
        if mode == .video,let maximumHeight {
            try await Task.detached {
                try enforceVideoHeight(results,maximum:maximumHeight,directory:area.directory,token:token,progress:progress)
            }.value
        }
        progress(OperationProgress.indeterminate,"Finishing your file…")
        try transaction.record(results,in:area)
        let output=try transaction.publish(token:token)
        progress(1,"Saved to \(destination.lastPathComponent)")
        return output
    }

    // Some sites omit dimensions or report stale values for their direct formats.
    // Verify the actual local file instead of trusting the format selector alone.
    static func enforceVideoHeight(_ files:[URL],maximum:Int,directory:URL,token:CancellationToken,progress:@escaping ProgressHandler) throws {
        for file in files {
            try token.check()
            let media=try MediaEngine.inspect(file,token:token)
            guard let height=media.video?.height else { throw NashiError.failed("The downloaded file has no readable video.") }
            guard height>maximum else { continue }
            progress(OperationProgress.indeterminate,"Fitting video to the selected size…")
            var options=OperationOptions();options.outputDirectory=directory;options.videoMaxHeight=maximum
            let converted=try MediaEngine.convert(file,to:"mp4",options:options,token:token,progress:{ value,_ in progress(value,"Fitting video to the selected size…") })
            guard converted.count==1,let replacement=converted.first,
                  let outputHeight=try MediaEngine.inspect(replacement,token:token).video?.height,outputHeight<=maximum else {
                throw NashiError.failed("The selected video size could not be applied.")
            }
            try token.check()
            try FileManager.default.removeItem(at:file)
            try FileManager.default.moveItem(at:replacement,to:file)
        }
    }

    static func baseArguments(photoPost:Bool=false) throws -> [String] {
        ["--ignore-config","--no-plugin-dirs","--no-update","--no-cache-dir","--no-remote-components",
         "--no-js-runtimes","--js-runtimes","deno:\(try Dependencies.executable("deno").path)",
         "--ffmpeg-location",try Dependencies.executable("ffmpeg").deletingLastPathComponent().path,
         "--socket-timeout","20","--retries","2","--extractor-retries","1","--no-colors"] +
        (photoPost ? ["--yes-playlist","--playlist-end","51"]:["--no-playlist","--playlist-items","1"])
    }
    static func downloadArguments(_ info:WebMediaInfo,mode:WebDownloadMode,maximumHeight:Int?,directory:URL) throws -> [String] {
        var args=try baseArguments()+["--no-simulate","--no-overwrites","--windows-filenames","--trim-filenames","180",
             "--downloader","native","--newline","--progress","--progress-template","download:NASHI_PROGRESS:%(progress._percent_str)s",
             "--print","before_dl:NASHI_STAGE:Preparing media…","--print","post_process:NASHI_STAGE:Finishing media…",
             "--output",directory.appendingPathComponent("%(title).120B [%(id).40B].%(ext)s").path,
             "--print","after_move:NASHI_FILE:%(filepath)j"]
        switch mode {
        case .audioMP3:args += ["--format","bestaudio/best","--extract-audio","--audio-format","mp3","--audio-quality","0"]
        case .video:
            let limit=maximumHeight.map{"[height<=?\($0)]"} ?? ""
            args += ["--format","bestvideo[ext=mp4]\(limit)+bestaudio[ext=m4a]/best[ext=mp4]\(limit)/bestvideo\(limit)+bestaudio/best\(limit)","--merge-output-format","mp4","--remux-video","mp4"]
        case .original:args += ["--format","bestaudio/best"]
        }
        return args+["--",info.url.absoluteString]
    }

    static func downloadDirect(_ info:WebMediaInfo,mode:WebDownloadMode,directory:URL,token:CancellationToken,
                                       progress:@escaping ProgressHandler) async throws -> [URL] {
        let temporary = directory.appendingPathComponent(".download-\(UUID().uuidString)")
        let response = try await PublicWebTransfer.fetchAsync(info.url, to: temporary, maximumBytes: 20 * 1024 * 1024 * 1024, token: token, progress: progress)
        defer { try? FileManager.default.removeItem(at:temporary) }
        try token.check();try Task.checkCancellation()
        guard (200...299).contains(response.statusCode),
              directKind(mime:response.mimeType,extension:info.url.pathExtension) != nil else { throw NashiError.failed("The link no longer returns a media file. Copy its current media or share link and try again.") }
        let name=cleanFilename(response.suggestedFilename ?? info.filename ?? info.title,mime:response.mimeType)
        let raw=directory.appendingPathComponent(name)
        try FileManager.default.moveItem(at:temporary,to:raw)
        try OutputFiles.validate([raw])
        if info.kind == .image { _=try ImageEngine.load(raw) }
        else { _=try await Task.detached { try MediaEngine.inspect(raw,token:token) }.value }
        if mode == .audioMP3,raw.pathExtension.lowercased() != "mp3" {
            var options=OperationOptions();options.outputDirectory=directory
            return try await Task.detached { try ConversionEngine.run(.init(inputs:[raw],operation:.convert("mp3"),options:options),token:token,progress:{ value,_ in progress(value,"Converting downloaded audio…") }) }.value
        }
        return [raw]
    }

    public static func directKind(mime:String?,extension ext:String)->WebMediaKind? {
        let mime=(mime ?? "").lowercased(),ext=ext.lowercased()
        if ["m3u8","mpd"].contains(ext) || mime.contains("mpegurl") || mime.contains("dash+xml") { return nil }
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        guard mime.isEmpty || mime=="application/octet-stream" else { return nil }
        if ["png","jpg","jpeg","webp","heic","heif","avif","bmp","tif","tiff"].contains(ext) { return .image }
        if ["mp4","mov","webm","mkv","m4v","gif"].contains(ext) { return .video }
        if ["mp3","m4a","wav","flac","ogg","opus","aac","aiff"].contains(ext) { return .audio }
        return nil
    }
    public static func cleanFilename(_ proposed:String,mime:String?)->String {
        var name=(proposed as NSString).lastPathComponent
        name=String(name.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0) && !CharacterSet(charactersIn:"/:\\").contains($0)}.prefix(170))
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name="Downloaded media" }
        let ext=(name as NSString).pathExtension.lowercased()
        let preferred=mime.flatMap{UTType(mimeType:$0)?.preferredFilenameExtension}
        let allowed=["jpg","jpeg","png","webp","heic","heif","avif","bmp","tif","tiff","svg","gif","mp4","mov","webm","mkv","m4v","mp3","m4a","wav","flac","ogg","opus","aac","aiff"]
        if !allowed.contains(ext),let preferred,allowed.contains(preferred) { name=(name as NSString).deletingPathExtension+"."+preferred }
        return name
    }
    public static func friendlyError(_ diagnostic:String)->String {
        let lower=diagnostic.lowercased()
        if lower.contains("sign in") || lower.contains("login") || lower.contains("cookies") || lower.contains("private") || lower.contains("age-restricted") { return "This link requires a login or is restricted. Try a public share link; Nashi does not read your browser sessions." }
        if lower.contains("drm") || lower.contains("protected") { return "This media is protected and cannot be downloaded here." }
        if lower.contains("unsupported url") || lower.contains("no video") || lower.contains("no media") { return "No downloadable media was found. Use the video's share link, or Copy Image Address for a photo." }
        if lower.contains("429") || lower.contains("rate limit") || lower.contains("too many requests") { return "The site is limiting requests. Wait a little and try again." }
        if lower.contains("403") || lower.contains("forbidden") || lower.contains("not available") || lower.contains("unavailable") { return "The site did not allow this download. The link may have expired or need a login." }
        return "The site could not provide this media. Try a fresh public share link or a direct media URL."
    }

}
