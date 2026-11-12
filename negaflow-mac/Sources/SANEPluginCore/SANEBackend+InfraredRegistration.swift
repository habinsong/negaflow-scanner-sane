import CoreGraphics
import Foundation
import ImageIO

/// IR 패스와 컬러 패스의 위치 어긋남을 스캔마다 잰다.
///
/// Epson Perfection V500 Photo 의 IR 패스는 같은 영역의 컬러 패스와 어긋나게 읽힌다. 어긋남은
/// 고정값이 아니다. 6400 dpi 컬러 기준으로 8 mm 크롭에서는 13 행 5 열이었고, 같은 장치의 전체
/// 프레임에서는 위쪽 -3 행에서 아래쪽 +1 행까지 변했으며 열은 4~9 였다. 그래서 컬러 휘도에서
/// 먼지가 만드는 어두운 점과 IR 먼지 지도를 대조해 스캔마다 이동량을 구하고, 프레임을 따라
/// 직선으로 변하는 모델(행 y 에서의 이동 = 상수 + 기울기 * y)로 맞춘다.
struct InfraredRegistration: Equatable {
    /// 컬러 격자 픽셀 단위. IR 내용이 컬러보다 아래·오른쪽으로 밀려 있으면 양수다.
    var dy0: Double
    var dyPerRow: Double
    var dx0: Double
    var dxPerRow: Double

    func shift(atRow y: Double) -> (dy: Double, dx: Double) {
        (dy0 + dyPerRow * y, dx0 + dxPerRow * y)
    }
}

extension SANEBackend {

    /// 컬러 TIFF 와 IR TIFF 로 이동량을 추정한다. 먼지가 모자라 믿을 수 없으면 nil.
    static func estimateInfraredRegistration(
        colorURL: URL,
        infraredURL: URL,
        minPointsPerBand: Int = 300,
        minScore: Double = -0.3
    ) throws -> InfraredRegistration? {
        let (colorWidth, colorHeight) = imageSize(at: colorURL)
        guard colorWidth > 0, colorHeight > 0 else { return nil }
        // 큰 프레임은 분석용으로 줄인다. 이동량은 마지막에 컬러 픽셀로 되돌린다.
        let factor = max(1, (max(colorWidth, colorHeight) + 4599) / 4600)
        let aw = colorWidth / factor, ah = colorHeight / factor

        let color = try loadGrayFloat(url: colorURL, width: aw, height: ah, deviceGray: true)
        let infrared = try loadGrayFloat(url: infraredURL, width: nil, height: nil, deviceGray: false)

        // 컬러 휘도의 국소 평균에서 벗어난 정도(먼지는 음수로 나온다)를 표준편차로 나눈다.
        let mean = boxMean(color.pixels, width: aw, height: ah, radius: max(4, 12 / factor))
        var residual = [Float](repeating: 0, count: aw * ah)
        var sum = 0.0, sumSquares = 0.0
        for i in 0..<residual.count {
            let r = color.pixels[i] - mean[i]
            residual[i] = r
            sum += Double(r)
            sumSquares += Double(r) * Double(r)
        }
        let n = Double(residual.count)
        let sd = (sumSquares / n - (sum / n) * (sum / n)).squareRoot()
        guard sd > 0 else { return nil }
        let inverseSD = Float(1 / sd)

        // IR 먼지 지도: 국소 평균보다 어두운 정도가 로버스트 표준편차의 4 배를 넘는 픽셀.
        let iw = infrared.width, ih = infrared.height
        let irMean = boxMean(infrared.pixels, width: iw, height: ih, radius: 7)
        var dust = [Float](repeating: 0, count: iw * ih)
        for i in 0..<dust.count { dust[i] = irMean[i] - infrared.pixels[i] }
        let robust = robustSigma(dust)
        guard robust > 0 else { return nil }
        let threshold = Float(4 * robust)

        let bands = 8
        let rangeY = (30 + factor - 1) / factor
        let rangeX = (14 + factor - 1) / factor
        var points: [(y: Double, dy: Int, dx: Int, score: Double)] = []
        for band in 0..<bands {
            let y0 = band * ah / bands, y1 = (band + 1) * ah / bands
            var ys: [Int] = [], xs: [Int] = []
            for iy in 0..<ih {
                let cy = min(ah - 1, Int((Double(iy) + 0.5) * Double(ah) / Double(ih)))
                if cy < y0 || cy >= y1 { continue }
                for ix in 0..<iw where dust[iy * iw + ix] > threshold {
                    ys.append(cy)
                    xs.append(min(aw - 1, Int((Double(ix) + 0.5) * Double(aw) / Double(iw))))
                }
            }
            guard ys.count >= minPointsPerBand else { continue }
            // 점이 많으면 일정 간격으로 줄인다.
            let stride = max(1, ys.count / 3000)
            var best = (score: Double.infinity, dy: 0, dx: 0)
            for dy in -rangeY...rangeY {
                for dx in -rangeX...rangeX {
                    var total = 0.0, count = 0
                    var k = 0
                    while k < ys.count {
                        let sy = ys[k] - dy, sx = xs[k] - dx
                        if sy >= 0, sy < ah, sx >= 0, sx < aw {
                            total += Double(residual[sy * aw + sx] * inverseSD)
                            count += 1
                        }
                        k += stride
                    }
                    if count >= 20 {
                        let score = total / Double(count)
                        if score < best.score { best = (score, dy, dx) }
                    }
                }
            }
            if best.score < minScore {
                points.append(((Double(y0 + y1) / 2) * Double(factor), best.dy * factor, best.dx * factor, best.score))
            }
        }
        guard !points.isEmpty else { return nil }
        if points.count == 1 {
            return InfraredRegistration(
                dy0: Double(points[0].dy), dyPerRow: 0, dx0: Double(points[0].dx), dxPerRow: 0
            )
        }
        let weights = points.map { -$0.score }
        let (dyIntercept, dySlope) = weightedLine(x: points.map { $0.y }, y: points.map { Double($0.dy) }, w: weights)
        let (dxIntercept, dxSlope) = weightedLine(x: points.map { $0.y }, y: points.map { Double($0.dx) }, w: weights)
        return InfraredRegistration(dy0: dyIntercept, dyPerRow: dySlope, dx0: dxIntercept, dxPerRow: dxSlope)
    }

    /// 가중 최소제곱 직선 y = a + b x.
    static func weightedLine(x: [Double], y: [Double], w: [Double]) -> (Double, Double) {
        let sw = w.reduce(0, +)
        let mx = zip(x, w).map { $0 * $1 }.reduce(0, +) / sw
        let my = zip(y, w).map { $0 * $1 }.reduce(0, +) / sw
        var sxx = 0.0, sxy = 0.0
        for i in 0..<x.count {
            sxx += w[i] * (x[i] - mx) * (x[i] - mx)
            sxy += w[i] * (x[i] - mx) * (y[i] - my)
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        return (my - slope * mx, slope)
    }

    /// 중앙값 절대편차로 구한 표준편차 추정치. 큰 배열은 일정 간격으로 줄여서 쓴다.
    static func robustSigma(_ values: [Float]) -> Double {
        let step = max(1, values.count / 200_000)
        var sample = [Float]()
        sample.reserveCapacity(values.count / step + 1)
        var i = 0
        while i < values.count { sample.append(values[i]); i += step }
        sample.sort()
        let median = sample[sample.count / 2]
        var deviations = sample.map { abs($0 - median) }
        deviations.sort()
        return 1.4826 * Double(deviations[deviations.count / 2])
    }

    /// 가장자리를 복제하는 상자 평균(반지름 radius).
    static func boxMean(_ a: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
        let window = Double(2 * r + 1)
        var tmp = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = y * w
            var sum = 0.0
            for i in -r...r { sum += Double(a[row + min(max(i, 0), w - 1)]) }
            for x in 0..<w {
                tmp[row + x] = Float(sum / window)
                sum += Double(a[row + min(x + r + 1, w - 1)]) - Double(a[row + max(x - r, 0)])
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        var column = [Double](repeating: 0, count: w)
        for i in -r...r {
            let yy = min(max(i, 0), h - 1)
            for x in 0..<w { column[x] += Double(tmp[yy * w + x]) }
        }
        for y in 0..<h {
            for x in 0..<w { out[y * w + x] = Float(column[x] / window) }
            let add = min(y + r + 1, h - 1), sub = max(y - r, 0)
            for x in 0..<w { column[x] += Double(tmp[add * w + x]) - Double(tmp[sub * w + x]) }
        }
        return out
    }

    /// TIFF 를 회색조 Float 배열로 읽는다. width/height 가 nil 이면 원래 크기를 쓴다.
    /// `deviceGray` 가 true 면 컬러 이미지를 휘도로 바꿔 읽고, false 면 원본 색공간을 그대로 쓴다.
    static func loadGrayFloat(
        url: URL, width: Int?, height: Int?, deviceGray: Bool
    ) throws -> (pixels: [Float], width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScannerError(.ioFailure, "TIFF 를 읽을 수 없습니다: \(url.lastPathComponent)")
        }
        let w = width ?? image.width, h = height ?? image.height
        let space = deviceGray ? CGColorSpaceCreateDeviceGray() : (image.colorSpace ?? CGColorSpaceCreateDeviceGray())
        guard space.model == .monochrome,
              let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
              ), let data = context.data else {
            throw ScannerError(.ioFailure, "분석용 비트맵을 만들 수 없습니다.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytesPerRow = context.bytesPerRow
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = data.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt16.self)
            for x in 0..<w { pixels[y * w + x] = Float(UInt16(littleEndian: row[x])) }
        }
        return (pixels, w, h)
    }
}
