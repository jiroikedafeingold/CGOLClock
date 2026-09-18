import CoreGraphics
import Foundation

/// Recycles frame buffers so rendering never allocates.
///
/// `CGContext.makeImage()` allocates and copies the whole bitmap every call.
/// At pixel resolution that is 12 MB a frame, and the cost is dominated by
/// first-touch page faults on the fresh allocation — it measured around 4 ms,
/// four times the cost of actually drawing the frame.
///
/// Instead each frame is drawn into a recycled buffer and handed to a
/// `CGDataProvider` that owns it. When Core Graphics releases the image the
/// buffer comes back here for reuse. Nothing is allocated or copied per frame.
nonisolated final class FrameBufferPool {
    private let texelCount: Int
    private let lock = NSLock()
    private var available: [UnsafeMutablePointer<UInt32>] = []
    /// Everything ever handed out, so `deinit` can free it all.
    private var allocated: [UnsafeMutablePointer<UInt32>] = []

    init(texelCount: Int, initialBuffers: Int = 3) {
        self.texelCount = texelCount
        for _ in 0..<initialBuffers {
            let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: texelCount)
            buffer.initialize(repeating: 0, count: texelCount)
            available.append(buffer)
            allocated.append(buffer)
        }
    }

    deinit {
        // Only reached once every outstanding image has released its buffer,
        // because each checkout retains the pool.
        for buffer in allocated { buffer.deallocate() }
    }

    /// A buffer nobody else is drawing into or displaying. Grows the pool
    /// rather than blocking if every buffer is still on screen.
    func take() -> UnsafeMutablePointer<UInt32> {
        lock.lock()
        defer { lock.unlock() }
        if let buffer = available.popLast() { return buffer }

        let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: texelCount)
        buffer.initialize(repeating: 0, count: texelCount)
        allocated.append(buffer)
        return buffer
    }

    fileprivate func give(_ buffer: UnsafeMutablePointer<UInt32>) {
        lock.lock()
        available.append(buffer)
        lock.unlock()
    }
}

/// Ties one buffer to the pool it came from for the lifetime of one image.
private final class Checkout {
    let pool: FrameBufferPool
    let buffer: UnsafeMutablePointer<UInt32>

    init(pool: FrameBufferPool, buffer: UnsafeMutablePointer<UInt32>) {
        self.pool = pool
        self.buffer = buffer
    }
}

extension FrameBufferPool {
    /// Wraps `buffer` in an image that returns it here when Core Graphics is
    /// finished with it. The caller must not touch the buffer afterwards.
    func image(
        from buffer: UnsafeMutablePointer<UInt32>,
        width: Int,
        height: Int
    ) -> CGImage? {
        let checkout = Checkout(pool: self, buffer: buffer)
        let info = Unmanaged.passRetained(checkout).toOpaque()

        guard
            let provider = CGDataProvider(
                dataInfo: info,
                data: buffer,
                size: width * height * MemoryLayout<UInt32>.size,
                releaseData: { info, _, _ in
                    guard let info else { return }
                    let checkout = Unmanaged<Checkout>.fromOpaque(info).takeRetainedValue()
                    checkout.pool.give(checkout.buffer)
                }
            )
        else {
            Unmanaged<Checkout>.fromOpaque(info).release()
            give(buffer)
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * MemoryLayout<UInt32>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
