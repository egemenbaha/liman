import Foundation
import CryptoKit

/// Public packages keep large upstream runtimes outside the signed app bundle.
/// Setup acquires exact upstream versions, verifies hashes, stages them and only
/// then publishes a complete tool directory. No credential store is involved.
public enum ExternalToolSetup {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Liman/Tools", isDirectory:true)
    }
    public static func executable(_ name:String)->URL? {
        let relative:String
        switch name {
        case "ffmpeg","ffprobe","yt-dlp","deno": relative="media-v1/\(name)"
        case "soffice": relative="office-26.8.1/LibreOffice.app/Contents/MacOS/soffice"
        default:return nil
        }
        let url=root.appendingPathComponent(relative)
        return usable(url) ? url:nil
    }
    private static func usable(_ url:URL)->Bool {
        guard let values=try? url.resolvingSymlinksInPath().resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]) else{return false}
        return FileManager.default.isExecutableFile(atPath:url.path) && values.isRegularFile == true && (values.fileSize ?? 0)>0
    }
    public static var status:ToolSetupStatus { ToolSetupStatus { try? Dependencies.executable($0) } }
    public static var mediaReady:Bool { status.mediaReady }
    public static var officeReady:Bool { status.officeReady }
    public static func installMedia(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if mediaReady { progress(1,"Media tools are ready.");return }
        let fm=FileManager.default;try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stage=root.appendingPathComponent(".media-\(UUID().uuidString)",isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:stage) }
        let packages:[(String,String,String,String?)] = [
            ("ffmpeg","https://www.osxexperts.net/ffmpeg9arm.zip","591260c945d0eef150e3bf82b0ef988bd36a9cecc18ff05d6679617159f0a95e","binary"),
            ("ffprobe","https://www.osxexperts.net/ffprobe9arm.zip","e11c17e8200b3ee4c4c186d245e2b4053f01d56957336c1817fca0b997469106","binary"),
            ("yt-dlp","https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos","0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202",nil),
            ("deno","https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip","5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c","archive")
        ]
        for (index,package) in packages.enumerated() {
            try token.check();try Task.checkCancellation()
            let archive=stage.appendingPathComponent("download-\(index)")
            try await CheckedToolDownload.fetch(URL(string:package.1)!,to:archive,maximum:400*1024*1024,token:token) { fraction in
                progress(fraction.map{(Double(index)+$0)/Double(packages.count)},"Downloading \(package.0)…")
            }
            if package.3 != "binary" { try verify(archive,digest:package.2) }
            let output=stage.appendingPathComponent(package.0)
            if package.3 != nil {
                let unpack=stage.appendingPathComponent("unpack-\(index)",isDirectory:true)
                try ArchiveCodec.extract(archive,into:unpack,token:token,limits:.init(maximumEntries:1000,maximumBytes:512*1024*1024))
                let candidate=unpack.appendingPathComponent(package.0)
                let values=try candidate.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                guard values.isRegularFile == true,values.isSymbolicLink != true else { throw NashiError.failed("Upstream package has no regular \(package.0) executable.") }
                if package.3 == "binary" { try verify(candidate,digest:package.2) }
                try fm.moveItem(at:candidate,to:output);try fm.removeItem(at:unpack)
            } else { try fm.moveItem(at:archive,to:output) }
            try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:output.path)
            if fm.fileExists(atPath:archive.path) { try fm.removeItem(at:archive) }
        }
        try token.check();try Task.checkCancellation()
        let target=root.appendingPathComponent("media-v1",isDirectory:true)
        try ToolInstallation.publish(stage,to:target) { directory in ["ffmpeg","ffprobe","yt-dlp","deno"].allSatisfy { usable(directory.appendingPathComponent($0)) } }
        progress(1,"Media tools are ready.")
    }
    public static func installOffice(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if officeReady { progress(1,"Office tools are ready.");return }
        let fm=FileManager.default;try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stage=root.appendingPathComponent(".office-\(UUID().uuidString)",isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer { try? fm.removeItem(at:stage) }
        let image=stage.appendingPathComponent("LibreOffice.dmg")
        try await CheckedToolDownload.fetch(URL(string:"https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg")!,to:image,maximum:400*1024*1024,token:token) { progress($0.map{$0*0.8},"Downloading LibreOffice 26.8.1…") }
        try verify(image,digest:"ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc")
        try token.check();try Task.checkCancellation();progress(nil,"Verifying and preparing office tools…")
        let mount=stage.appendingPathComponent("mount",isDirectory:true);try fm.createDirectory(at:mount,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["attach","-nobrowse","-readonly","-mountpoint",mount.path,image.path],token:token)
        defer { _ = try? ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["detach",mount.path]) }
        let content=stage.appendingPathComponent("content",isDirectory:true);try fm.createDirectory(at:content,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/ditto"),[mount.appendingPathComponent("LibreOffice.app").path,content.appendingPathComponent("LibreOffice.app").path],token:token)
        try token.check();try Task.checkCancellation()
        let target=root.appendingPathComponent("office-26.8.1",isDirectory:true)
        try ToolInstallation.publish(content,to:target) { usable($0.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice")) }
        progress(1,"Office tools are ready.")
    }
    static func verify(_ file:URL,digest:String) throws {
        let input=try FileHandle(forReadingFrom:file);defer{try? input.close()};var hasher=SHA256()
        while let bytes=try input.read(upToCount:1024*1024),!bytes.isEmpty {hasher.update(data:bytes)}
        let actual=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        guard actual == digest else {throw NashiError.failed("The upstream download checksum did not match. Nothing was installed.")}
    }
}

private enum CheckedToolDownload {
    static func fetch(_ url:URL,to target:URL,maximum:Int64,token:CancellationToken,progress:@escaping @Sendable (Double?)->Void) async throws {
        guard url.scheme == "https" else { throw PublicWebPolicy.refused() }
        let response = try await PublicWebTransfer.fetchAsync(url,to:target,maximumBytes:maximum,token:token) { fraction,_ in
            progress(fraction >= 0 ? fraction:nil)
        }
        guard (200...299).contains(response.statusCode), response.url?.scheme == "https",
              (try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) > 0 else {
            try? FileManager.default.removeItem(at:target)
            throw NashiError.failed("The upstream server did not return a successful HTTPS download.")
        }
    }
}
