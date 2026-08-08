import Foundation

extension SANEBackend {
    static func alignedSourceIndex(
        x: Int,
        y: Int,
        channel: Int,
        offset: (x: Int, y: Int),
        width: Int,
        height: Int
    ) -> Int? {
        let sx = x + offset.x
        let sy = y + offset.y
        guard sx >= 0, sx < width, sy >= 0, sy < height else { return nil }
        return (sy * width + sx) * 4 + channel
    }

    static func exposureTrustWeight(_ rawValue: Float) -> Float {
        if rawValue >= 0.985 { return 0.02 }
        if rawValue >= 0.90 {
            return max(0.05, (0.985 - rawValue) / 0.085)
        }
        if rawValue <= 0.006 { return 0.02 }
        if rawValue <= 0.035 {
            return max(0.05, (rawValue - 0.006) / 0.029)
        }
        return 1
    }

    static func mix(_ a: Float, _ b: Float, _ amount: Float) -> Float {
        let t = min(max(amount, 0), 1)
        return a + (b - a) * t
    }

    static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge0 != edge1 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func estimateIntegerOffset(
        reference: [Float],
        sample: [Float],
        width: Int,
        height: Int
    ) -> (x: Int, y: Int) {
        // 다운샘플 배율은 이미지 크기에 적응(작은 이미지/테스트에선 1px 정렬도 가능하게).
        let factor = max(1, min(8, min(width, height) / 96))
        let (ref, dw, dh) = downsampledLuma(reference, width: width, height: height, factor: factor)
        let (smp, _, _) = downsampledLuma(sample, width: width, height: height, factor: factor)
        guard dw > 6, dh > 6 else { return (0, 0) }
        // 텍스처 가드는 휘도 레벨에 상대적으로 둔다 — 네거티브 raw는 절대 휘도가 낮아(ADC 일부만 사용)
        // 고정 임계면 구조가 충분한데도 항상 스킵돼 정렬이 (0,0)으로 빠진다. 평균 대비 비율로 판정.
        let refMean = max(ref.reduce(0, +) / Float(max(ref.count, 1)), 1e-6)
        guard downsampledTexture(ref, width: dw, height: dh) > Double(refMean) * 0.008 else { return (0, 0) }

        let baseline = downsampledError(ref, smp, width: dw, height: dh, dx: 0, dy: 0)
        var best = (x: 0, y: 0)
        var bestError = baseline
        let yRange = max(1, min(96 / factor, (dh - 6) / 2))   // 세로/이송 축 — 넓게(이미지 범위 내로 클램프)
        let xRange = max(1, min(16 / factor, (dw - 6) / 2))   // 가로/크로스피드 — 좁게
        for dy in -yRange...yRange {
            for dx in -xRange...xRange {
                let error = downsampledError(ref, smp, width: dw, height: dh, dx: dx, dy: dy)
                if error < bestError { bestError = error; best = (dx, dy) }
            }
        }
        guard bestError < baseline * 0.85 else { return (0, 0) }

        // 풀해상도 미세보정: 다운샘플 최적점(×factor) 주변 ±factor(세로)·±2(가로).
        var fx = best.x * factor
        var fy = best.y * factor
        var fineError = fullResLumaError(reference, sample, width: width, height: height, dx: fx, dy: fy)
        for dy in (fy - factor)...(fy + factor) {
            for dx in (fx - 2)...(fx + 2) {
                let error = fullResLumaError(reference, sample, width: width, height: height, dx: dx, dy: dy)
                if error < fineError { fineError = error; fx = dx; fy = dy }
            }
        }
        return (fx, fy)
    }

    /// factor×factor 블록 평균으로 휘도를 다운샘플(노이즈 억제 + 빠른 탐색).
    private static func downsampledLuma(_ pixels: [Float], width: Int, height: Int, factor: Int) -> (luma: [Float], width: Int, height: Int) {
        let dw = width / factor, dh = height / factor
        guard dw > 0, dh > 0 else { return ([], 0, 0) }
        var out = [Float](repeating: 0, count: dw * dh)
        let inv = 1.0 / Float(factor * factor)
        for by in 0..<dh {
            let y0 = by * factor
            for bx in 0..<dw {
                let x0 = bx * factor
                var sum: Float = 0
                for yy in y0..<(y0 + factor) {
                    let row = yy * width
                    for xx in x0..<(x0 + factor) {
                        let i = (row + xx) * 4
                        sum += pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722
                    }
                }
                out[by * dw + bx] = sum * inv
            }
        }
        // 3x3 블러로 미세 패턴/노이즈를 죽인다 → 정렬이 거친 구조(장면)에만 반응(노이즈는 정렬하지 않음).
        return (boxBlur3(out, width: dw, height: dh), dw, dh)
    }

    /// 분리형 3x3 박스 블러.
    private static func boxBlur3(_ buf: [Float], width: Int, height: Int) -> [Float] {
        guard width >= 3, height >= 3 else { return buf }
        let third: Float = 1.0 / 3.0
        var tmp = buf
        for y in 0..<height {
            let r = y * width
            for x in 1..<(width - 1) {
                tmp[r + x] = (buf[r + x - 1] + buf[r + x] + buf[r + x + 1]) * third
            }
        }
        var out = tmp
        for y in 1..<(height - 1) {
            for x in 0..<width {
                out[y * width + x] = (tmp[(y - 1) * width + x] + tmp[y * width + x] + tmp[(y + 1) * width + x]) * third
            }
        }
        return out
    }

    private static func downsampledError(_ ref: [Float], _ smp: [Float], width: Int, height: Int, dx: Int, dy: Int) -> Double {
        let inset = 2 + max(abs(dx), abs(dy))
        guard width > 2 * inset, height > 2 * inset else { return .greatestFiniteMagnitude }
        var total = 0.0
        var count = 0
        for y in inset..<(height - inset) {
            let rRow = y * width, sRow = (y + dy) * width
            for x in inset..<(width - inset) {
                total += abs(Double(ref[rRow + x] - smp[sRow + x + dx]))
                count += 1
            }
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private static func downsampledTexture(_ luma: [Float], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                total += abs(Double(luma[row + x] - luma[row + x + 1]))
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private static func fullResLumaError(_ reference: [Float], _ sample: [Float], width: Int, height: Int, dx: Int, dy: Int) -> Double {
        let step = max(1, min(width, height) / 256)
        let inset = 4 + max(abs(dx), abs(dy))
        guard width > 2 * inset, height > 2 * inset else { return .greatestFiniteMagnitude }
        var total = 0.0
        var count = 0
        var y = inset
        while y < height - inset {
            let sy = y + dy
            var x = inset
            while x < width - inset {
                let r = (y * width + x) * 4
                let s = (sy * width + x + dx) * 4
                let rl = reference[r] * 0.2126 + reference[r + 1] * 0.7152 + reference[r + 2] * 0.0722
                let sl = sample[s] * 0.2126 + sample[s + 1] * 0.7152 + sample[s + 2] * 0.0722
                total += abs(Double(rl - sl))
                count += 1
                x += step
            }
            y += step
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    static func accumulateAligned(
        _ sample: [Float],
        offset: (x: Int, y: Int),
        width: Int,
        height: Int,
        into accumulator: inout [Float],
        counts: inout [Float]
    ) {
        for y in 0..<height {
            let sy = y + offset.y
            guard sy >= 0, sy < height else { continue }
            for x in 0..<width {
                let sx = x + offset.x
                guard sx >= 0, sx < width else { continue }
                let source = (sy * width + sx) * 4
                let destination = (y * width + x) * 4
                accumulator[destination] += sample[source]
                accumulator[destination + 1] += sample[source + 1]
                accumulator[destination + 2] += sample[source + 2]
                counts[y * width + x] += 1
            }
        }
    }
}
