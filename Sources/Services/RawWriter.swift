import Darwin
import Foundation

private let rawChunkSize = 4 * 1024 * 1024

// <sys/disk.h>: the _IOR macros are not imported into Swift.
private let ioctlGetBlockSize: UInt = 0x4004_6418   // DKIOCGETBLOCKSIZE  (uint32_t)
private let ioctlGetBlockCount: UInt = 0x4008_6419  // DKIOCGETBLOCKCOUNT (uint64_t)

enum RawWriteError: LocalizedError {
    case validation(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .cancelled:
            return "Authorization cancelled: nothing was written."
        case .failed(let message):
            return message
        }
    }
}

/// Writes an image to a block device through `authopen`.
///
/// `authopen -stdoutpipe` opens the device once (with administrator
/// authorization) and hands the file descriptor to the app via SCM_RIGHTS.
/// Writing and verification share the same fd, a single prompt is enough,
/// and the app does not need Full Disk Access.
@MainActor
enum RawWriter {
    struct Update {
        let fraction: Double?
        let phase: BurnPhase
        let log: String?
    }

    static func write(
        image: URL,
        target: RawTarget,
        verify: Bool,
        onUpdate: @escaping @MainActor (Update) -> Void
    ) async throws {
        try await validate(image: image, target: target)

        let size = imageSize(image)
        let rawDevice = "/dev/r" + target.device.replacingOccurrences(of: "/dev/", with: "")

        onUpdate(Update(fraction: 0, phase: .preparing, log: "Unmounting \(target.device)…"))
        try await unmount(device: target.device)

        onUpdate(
            Update(
                fraction: 0,
                phase: .writing,
                log: "Requesting authorization for \(rawDevice)…"
            )
        )

        let fd = try await openAuthorizedDevice(rawDevice)

        do {
            // Is the opened device still the one that was confirmed? Re-check on
            // the descriptor itself, after the authorization prompt.
            let geometry = try deviceGeometry(fd)
            guard geometry.totalBytes == target.size else {
                throw RawWriteError.validation(
                    "The drive changed after confirmation. Refresh the list and try again."
                )
            }
            let paddedSize = (size + Int64(geometry.blockSize) - 1)
                / Int64(geometry.blockSize) * Int64(geometry.blockSize)
            guard paddedSize <= geometry.totalBytes else {
                throw RawWriteError.validation("The image is larger than the drive.")
            }
            onUpdate(
                Update(
                    fraction: 0,
                    phase: .writing,
                    log: "Drive sector size: \(geometry.blockSize) bytes."
                )
            )

            onUpdate(Update(fraction: 0, phase: .writing, log: "Starting write…"))
            try await writeImage(
                image: image,
                fd: fd,
                size: size,
                blockSize: geometry.blockSize,
                onUpdate: onUpdate
            )

            if fsync(fd) != 0 {
                let code = errno
                // Some raw devices do not support fsync: that is not a write error.
                if ![ENOTSUP, ENOTTY, EINVAL].contains(code) {
                    throw RawWriteError.failed(
                        "Error while finishing the write (errno \(code))."
                    )
                }
            }
            onUpdate(Update(fraction: 1, phase: .writing, log: "Write complete."))

            if verify {
                onUpdate(
                    Update(
                        fraction: 0,
                        phase: .verifying,
                        log: "Verifying: comparing the first \(size) bytes…"
                    )
                )
                try await verifyImage(
                    image: image,
                    fd: fd,
                    size: size,
                    blockSize: geometry.blockSize,
                    onUpdate: onUpdate
                )
                onUpdate(Update(fraction: 1, phase: .verifying, log: "Verification OK."))
            }
        } catch {
            close(fd)
            throw error
        }

        close(fd)
        await Task.detached(priority: .utility) { sync() }.value

        onUpdate(Update(fraction: 1, phase: .ejecting, log: "Ejecting…"))
        let eject = await Shell.run("/usr/sbin/diskutil", ["eject", target.device])
        if !eject.succeeded {
            onUpdate(
                Update(
                    fraction: 1,
                    phase: .ejecting,
                    log: "Eject failed: you can remove the drive manually."
                )
            )
        }

        onUpdate(Update(fraction: 1, phase: .done, log: nil))
    }

    // MARK: - Validation

    private static func validate(image: URL, target: RawTarget) async throws {
        guard let info = await DriveService.diskInfo(target.id) else {
            throw RawWriteError.validation("Disk \(target.device) is no longer available.")
        }

        if let problem = DriveService.eligibilityProblem(info) {
            throw RawWriteError.validation(problem)
        }

        guard let bootDisks = await DriveService.bootWholeDisks() else {
            throw RawWriteError.validation(
                "Cannot determine the startup disk: write aborted for safety."
            )
        }
        if bootDisks.contains(target.id) {
            throw RawWriteError.validation("Refused: the selected disk is the startup disk.")
        }

        // Is the disk still the one the user confirmed?
        let total = (info["TotalSize"] as? NSNumber)?.int64Value ?? target.size
        let mediaName = (info["MediaName"] as? String) ?? ""
        if total != target.size || (!mediaName.isEmpty && mediaName != target.name) {
            throw RawWriteError.validation(
                "The drive changed after confirmation. Refresh the list and try again."
            )
        }

        let imageBytes = imageSize(image)
        guard imageBytes > 0 else {
            throw RawWriteError.validation("The image is empty or unreadable.")
        }
        guard imageBytes <= total else {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            throw RawWriteError.validation(
                "The image (\(formatter.string(fromByteCount: imageBytes))) is larger than the drive (\(formatter.string(fromByteCount: total)))."
            )
        }
    }

    // MARK: - Unmounting

    private static func unmount(device: String) async throws {
        var result = await Shell.run("/usr/sbin/diskutil", ["unmountDisk", "force", device])
        if result.succeeded { return }

        // Second attempt: Spotlight or the Finder sometimes keep the volume
        // busy for a moment.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        result = await Shell.run("/usr/sbin/diskutil", ["unmountDisk", "force", device])
        if result.succeeded { return }

        let detail = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        throw RawWriteError.failed(
            "Could not unmount \(device). Quit any apps using it and try again."
                + (detail.isEmpty ? "" : "\n\(detail)")
        )
    }

    // MARK: - Authorized open

    /// `authopen` waits for the password: the blocking wait runs on a
    /// dedicated thread so it does not tie up the Swift concurrency pool.
    private nonisolated static func openAuthorizedDevice(_ path: String) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do {
                    continuation.resume(returning: try receiveAuthorizedDescriptor(path))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.name = "IsoQuik.authopen"
            thread.start()
        }
    }

    private nonisolated static func receiveAuthorizedDescriptor(_ path: String) throws -> Int32 {
        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            throw RawWriteError.failed(
                "Could not create the channel to authopen (errno \(errno))."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/authopen")
        process.arguments = ["-stdoutpipe", "-w", path]
        process.standardOutput = FileHandle(fileDescriptor: fds[1], closeOnDealloc: false)
        process.standardInput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            close(fds[0])
            close(fds[1])
            throw RawWriteError.failed("Could not launch authopen: \(error.localizedDescription)")
        }
        close(fds[1])

        var payload: UInt8 = 0
        var iov = iovec()
        var control = [UInt8](repeating: 0, count: 256)
        var message = msghdr()

        let received: Int32 = withUnsafeMutablePointer(to: &payload) { payloadPtr in
            withUnsafeMutablePointer(to: &iov) { iovPtr in
                iovPtr.pointee.iov_base = UnsafeMutableRawPointer(payloadPtr)
                iovPtr.pointee.iov_len = 1
                message.msg_iov = iovPtr
                message.msg_iovlen = 1

                return control.withUnsafeMutableBytes { controlPtr -> Int32 in
                    message.msg_control = controlPtr.baseAddress
                    message.msg_controllen = socklen_t(controlPtr.count)

                    let bytes = recvmsg(fds[0], &message, 0)
                    guard bytes >= 0 else { return -1 }

                    var result: Int32 = -1
                    let headerSize = MemoryLayout<cmsghdr>.size
                    let dataOffset = (headerSize + 3) & ~3
                    guard message.msg_controllen >= socklen_t(headerSize),
                          let base = message.msg_control else {
                        return -1
                    }

                    var current = base.assumingMemoryBound(to: cmsghdr.self)
                    var remaining = Int(message.msg_controllen)
                    while remaining >= headerSize {
                        let cmsg = current.pointee
                        if cmsg.cmsg_level == SOL_SOCKET,
                           cmsg.cmsg_type == SCM_RIGHTS,
                           Int(cmsg.cmsg_len) >= dataOffset + MemoryLayout<Int32>.size {
                            result = UnsafeMutableRawPointer(current)
                                .advanced(by: dataOffset)
                                .assumingMemoryBound(to: Int32.self)
                                .pointee
                            break
                        }

                        let step = (Int(cmsg.cmsg_len) + 3) & ~3
                        if step <= 0 || step > remaining { break }
                        remaining -= step
                        current = UnsafeMutableRawPointer(current)
                            .advanced(by: step)
                            .assumingMemoryBound(to: cmsghdr.self)
                    }
                    return result
                }
            }
        }

        close(fds[0])
        process.waitUntilExit()
        let stderr = readAll(errorPipe).trimmingCharacters(in: .whitespacesAndNewlines)

        guard received >= 0 else {
            if isCancellation(stderr) {
                throw RawWriteError.cancelled
            }
            throw RawWriteError.failed(
                stderr.isEmpty ? "macOS did not grant authorization." : stderr
            )
        }

        return received
    }

    // MARK: - Geometry

    private nonisolated static func deviceGeometry(_ fd: Int32) throws -> (blockSize: Int, totalBytes: Int64) {
        var blockSize: UInt32 = 0
        var blockCount: UInt64 = 0
        guard ioctl(fd, ioctlGetBlockSize, &blockSize) == 0,
              ioctl(fd, ioctlGetBlockCount, &blockCount) == 0 else {
            throw RawWriteError.failed(
                "Could not read the drive geometry (errno \(errno))."
            )
        }
        let size = Int(blockSize)
        guard size > 0, size & (size - 1) == 0, rawChunkSize % size == 0 else {
            throw RawWriteError.failed("Unsupported sector size: \(size) bytes.")
        }
        return (size, Int64(blockCount) * Int64(size))
    }

    // MARK: - Writing

    private nonisolated static func writeImage(
        image: URL,
        fd: Int32,
        size: Int64,
        blockSize: Int,
        onUpdate: @escaping @MainActor (Update) -> Void
    ) async throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: image)
        } catch {
            throw RawWriteError.failed("Could not read the image: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var written: Int64 = 0
        while written < size {
            let remaining = size - written
            let toRead = Int(min(Int64(rawChunkSize), remaining))
            let data = try readExactly(handle, count: toRead)
            guard data.count == toRead else {
                throw RawWriteError.failed("The image ended earlier than expected.")
            }

            // Pad the last block with zeros to a full sector: raw devices
            // require aligned I/O.
            let padding = (blockSize - (data.count % blockSize)) % blockSize
            var output = data
            if padding > 0 {
                output.append(Data(repeating: 0, count: padding))
            }

            try writeAll(fd: fd, data: output, offset: written)
            written += Int64(data.count)

            let fraction = size > 0
                ? min(max(Double(written) / Double(size), 0), 1)
                : nil
            await MainActor.run {
                onUpdate(Update(fraction: fraction, phase: .writing, log: nil))
            }
        }
    }

    private nonisolated static func writeAll(fd: Int32, data: Data, offset: Int64) throws {
        var position = offset
        var index = 0

        while index < data.count {
            let written = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return pwrite(
                    fd,
                    base.advanced(by: index),
                    data.count - index,
                    off_t(position)
                )
            }

            if written < 0 {
                if errno == EINTR { continue }
                throw RawWriteError.failed("Write error on the drive (errno \(errno)).")
            }
            if written == 0 {
                throw RawWriteError.failed("The drive does not accept any more data.")
            }

            index += written
            position += Int64(written)
        }
    }

    // MARK: - Verification

    private nonisolated static func verifyImage(
        image: URL,
        fd: Int32,
        size: Int64,
        blockSize: Int,
        onUpdate: @escaping @MainActor (Update) -> Void
    ) async throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: image)
        } catch {
            throw RawWriteError.failed("Could not reopen the image for verification.")
        }
        defer { try? handle.close() }

        var compared: Int64 = 0
        while compared < size {
            let remaining = size - compared
            let chunk = Int(min(Int64(rawChunkSize), remaining))
            let aligned = (chunk + blockSize - 1) / blockSize * blockSize

            let deviceData = try preadExactly(fd: fd, count: aligned, offset: compared)
            guard deviceData.count >= chunk else {
                throw RawWriteError.failed(
                    "Verification failed: the drive returned less data than expected."
                )
            }

            let imageData = try readExactly(handle, count: chunk)
            guard imageData.count == chunk else {
                throw RawWriteError.failed("Verification failed: image unreadable.")
            }

            let deviceSlice = Data(deviceData.prefix(chunk))
            if deviceSlice != imageData {
                let difference = firstDifference(deviceSlice, imageData)
                throw RawWriteError.failed(
                    "Verification failed: mismatch at byte \(compared + Int64(difference))."
                )
            }

            compared += Int64(chunk)
            let fraction = size > 0 ? Double(compared) / Double(size) : nil
            await MainActor.run {
                onUpdate(Update(fraction: fraction, phase: .verifying, log: nil))
            }
        }
    }

    private nonisolated static func preadExactly(fd: Int32, count: Int, offset: Int64) throws -> Data {
        var data = Data(count: count)
        var done = 0

        while done < count {
            let read = data.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return pread(
                    fd,
                    base.advanced(by: done),
                    count - done,
                    off_t(offset + Int64(done))
                )
            }

            if read < 0 {
                if errno == EINTR { continue }
                throw RawWriteError.failed("Read error on the drive (errno \(errno)).")
            }
            if read == 0 { break }
            done += read
        }

        return Data(data.prefix(done))
    }

    // MARK: - Utilities

    private nonisolated static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let chunk = try handle.read(upToCount: count - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    private nonisolated static func firstDifference(_ a: Data, _ b: Data) -> Int {
        let count = min(a.count, b.count)
        for index in 0..<count where a[a.startIndex + index] != b[b.startIndex + index] {
            return index
        }
        return count
    }

    private nonisolated static func readAll(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private nonisolated static func isCancellation(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("cancel")
            || lowercased.contains("annull") // authopen may reply in the system language
            || lowercased.contains("-128")
    }

    private nonisolated static func imageSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
