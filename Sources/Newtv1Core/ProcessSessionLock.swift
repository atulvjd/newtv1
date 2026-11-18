import Foundation
import Darwin

/// An advisory per-user lock shared by installed, development and DMG copies.
/// The kernel releases it on exit, including crashes. Never unlink a lock file:
/// another process may already have opened that inode.
public final class ProcessSessionLock {
    private let descriptor: Int32
    public let acquired: Bool

    public init(url: URL) throws {
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            throw POSIXError(.EACCES)
        }
        let result = flock(fd, LOCK_EX | LOCK_NB)
        let failure = errno
        guard result == 0 || failure == EWOULDBLOCK else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        descriptor = fd
        acquired = result == 0
    }

    deinit { close(descriptor) }
}
