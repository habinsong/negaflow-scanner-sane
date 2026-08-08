import Foundation
import CoreGraphics
import CoreImage

extension SANEBackend {
    static func alignedAverageRGBAf(
        _ images: [CIImage],
        colorSpace linear: CGColorSpace
    ) throws -> (pixels: [Float], width: Int, height: Int) {
        guard let first = images.first else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let extent = first.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 크기 오류")
        }

        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        let rendered = images.map { image in
            renderRGBAf(image.cropped(to: extent), width: width, height: height, context: context, colorSpace: linear)
        }
        guard let reference = rendered.first else {
            throw ScannerError(.ioFailure, "multi-sample TIFF 로드 실패")
        }
        let offsets = rendered.map { estimateIntegerOffset(reference: reference, sample: $0, width: width, height: height) }
        var accumulator = [Float](repeating: 0, count: width * height * 4)
        var counts = [Float](repeating: 0, count: width * height)
        for (sample, offset) in zip(rendered, offsets) {
            accumulateAligned(sample, offset: offset, width: width, height: height, into: &accumulator, counts: &counts)
        }
        for pixel in 0..<(width * height) {
            let count = max(counts[pixel], 1)
            let offset = pixel * 4
            accumulator[offset] = min(max(accumulator[offset] / count, 0), 1)
            accumulator[offset + 1] = min(max(accumulator[offset + 1] / count, 0), 1)
            accumulator[offset + 2] = min(max(accumulator[offset + 2] / count, 0), 1)
            accumulator[offset + 3] = 1
        }
        return (accumulator, width, height)
    }

    static func alignedExposureNormalizedRGBAf(
        _ images: [CIImage],
        exposureTimes: [Int],
        referenceExposure: Int,
        colorSpace linear: CGColorSpace
    ) throws -> (pixels: [Float], width: Int, height: Int) {
        let first = images[0]
        let extent = first.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else {
            throw ScannerError(.ioFailure, "hardware exposure TIFF 크기 오류")
        }

        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
        ])
        let rendered = images.map { image in
            renderRGBAf(image.cropped(to: extent), width: width, height: height, context: context, colorSpace: linear)
        }
        let normalized = zip(rendered, exposureTimes).map { sample, exposureTime in
            normalizeExposure(sample, exposureTime: exposureTime, referenceExposure: referenceExposure)
        }
        let referenceIndex = exposureTimes.enumerated()
            .min { abs($0.element - referenceExposure) < abs($1.element - referenceExposure) }?
            .offset ?? 0
        let reference = normalized[referenceIndex]
        let offsets = normalized.map { estimateIntegerOffset(reference: reference, sample: $0, width: width, height: height) }
        var merged = [Float](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let destination = (y * width + x) * 4
                for channel in 0..<3 {
                    merged[destination + channel] = mergedHardwareExposureValue(
                        x: x,
                        y: y,
                        channel: channel,
                        rendered: rendered,
                        normalized: normalized,
                        exposureTimes: exposureTimes,
                        referenceExposure: referenceExposure,
                        referenceIndex: referenceIndex,
                        offsets: offsets,
                        width: width,
                        height: height
                    )
                }
                merged[destination + 3] = 1
            }
        }
        return (merged, width, height)
    }

    private static func normalizeExposure(_ pixels: [Float], exposureTime: Int, referenceExposure: Int) -> [Float] {
        let scale = Float(referenceExposure) / Float(exposureTime)
        var out = pixels
        for index in stride(from: 0, to: out.count, by: 4) {
            out[index] *= scale
            out[index + 1] *= scale
            out[index + 2] *= scale
            out[index + 3] = 1
        }
        return out
    }

    private static func mergedHardwareExposureValue(
        x: Int,
        y: Int,
        channel: Int,
        rendered: [[Float]],
        normalized: [[Float]],
        exposureTimes: [Int],
        referenceExposure: Int,
        referenceIndex: Int,
        offsets: [(x: Int, y: Int)],
        width: Int,
        height: Int
    ) -> Float {
        let referenceSource = alignedSourceIndex(
            x: x,
            y: y,
            channel: channel,
            offset: offsets[referenceIndex],
            width: width,
            height: height
        )
        let fallback = (y * width + x) * 4 + channel
        let baselineIndex = referenceSource ?? min(fallback, normalized[referenceIndex].count - 1)
        let baselineRaw = rendered[referenceIndex][baselineIndex]

        var value = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 == referenceExposure }
        ) ?? normalized[referenceIndex][baselineIndex]
        if let short = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 < referenceExposure }
        ) {
            let amount = smoothstep(edge0: 0.82, edge1: 0.97, x: baselineRaw)
            value = mix(value, short, amount)
        }
        if let long = alternateExposureValue(
            x: x,
            y: y,
            channel: channel,
            rendered: rendered,
            normalized: normalized,
            exposureTimes: exposureTimes,
            offsets: offsets,
            width: width,
            height: height,
            matching: { $0 > referenceExposure }
        ) {
            let amount = (1 - smoothstep(edge0: 0.010, edge1: 0.045, x: baselineRaw)) * 0.48
            value = mix(value, long, amount)
        }
        return min(max(value, 0), 1)
    }

    private static func alternateExposureValue(
        x: Int,
        y: Int,
        channel: Int,
        rendered: [[Float]],
        normalized: [[Float]],
        exposureTimes: [Int],
        offsets: [(x: Int, y: Int)],
        width: Int,
        height: Int,
        matching predicate: (Int) -> Bool
    ) -> Float? {
        var weightedSum: Float = 0
        var weightSum: Float = 0
        for index in rendered.indices where predicate(exposureTimes[index]) {
            guard let source = alignedSourceIndex(
                x: x,
                y: y,
                channel: channel,
                offset: offsets[index],
                width: width,
                height: height
            ) else {
                continue
            }
            let rawValue = rendered[index][source]
            let weight = exposureTrustWeight(rawValue)
            weightedSum += normalized[index][source] * weight
            weightSum += weight
        }
        guard weightSum > 0.0001 else { return nil }
        return weightedSum / weightSum
    }
}
