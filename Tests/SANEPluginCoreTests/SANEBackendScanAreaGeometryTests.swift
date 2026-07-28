import XCTest
@testable import SANEPluginCore

/// epson2의 스캔 라인 수 계산 결함에 대한 회귀 테스트.
///
/// backend/epson2-ops.c의 `e2_init_parameters`는 라인 수를 다시 계산할 때
///
///     s->params.lines = ((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi + 0.5) - s->top;
///
/// 로 쓴다. C에서 캐스트가 나눗셈보다 먼저 묶이므로 br_y가 **정수 mm로 잘린다**.
/// 폭 계산(`pixels_per_line`)은 같은 실수를 하지 않기 때문에 세로만 최대 1mm어치 짧아지고,
/// 결과 이미지의 종횡비가 요청과 어긋난다. sane-backends 1.4.0과 master 모두 동일하다.
///
/// 실기 없이 검증하기 위해 위 산술을 그대로 옮겨두고, 정렬 전에는 손실이 발생하며
/// 정렬 후에는 사라진다는 것을 수치로 확인한다.
final class SANEBackendScanAreaGeometryTests: XCTestCase {

    private static let millimetersPerInch = 25.4

    /// epson2-ops.c가 계산하는 출력 픽셀 크기(관련 부분만 그대로 옮김).
    private static func epson2OutputPixels(
        originXMM: Double,
        originYMM: Double,
        widthMM: Double,
        heightMM: Double,
        dpi: Int
    ) -> (width: Int, height: Int) {
        let dpi = Double(dpi)
        let bottomMM = originYMM + heightMM
        // epson2-ops.c:1309 / :1312 / :1315
        let top = Int(originYMM / millimetersPerInch * dpi + 0.5)
        var lines = Int(heightMM / millimetersPerInch * dpi + 0.5)
        var pixelsPerLine = Int(widthMM / millimetersPerInch * dpi + 0.5)
        // epson2-ops.c:1420 — (int) 캐스트가 br_y를 정수 mm로 자른다.
        if bottomMM / millimetersPerInch * dpi < Double(lines + top) {
            lines = Int(Double(Int(bottomMM)) / millimetersPerInch * dpi + 0.5) - top
        }
        // epson2-ops.c:1358 — 폭은 8의 배수로 내림.
        pixelsPerLine &= ~7
        return (pixelsPerLine, lines)
    }

    /// 앱이 쓰는 종횡비 검사와 같은 판정(허용치 2%, 하한 3px).
    private static func aspectMismatches(
        width: Int,
        height: Int,
        widthMM: Double,
        heightMM: Double
    ) -> Bool {
        let expectedWidth = Double(height) * widthMM / heightMM
        let allowed = max(3, max(Double(width), expectedWidth) * 0.02)
        return abs(Double(width) - expectedWidth) > allowed
    }

    /// 결정적 스윕: 원점을 0.01mm 간격으로 옮기며 프레임 크기·해상도별 손실을 측정한다.
    private func sweep(
        widthMM: Double,
        heightMM: Double,
        dpi: Int,
        aligning: Bool
    ) -> (mismatchRate: Double, worstHeightLoss: Double, worstGrowthMM: Double) {
        var mismatches = 0
        var worstLoss = 0.0
        var worstGrowth = 0.0
        let samples = 2000
        for step in 0..<samples {
            let originYMM = Double(step) * 0.0917          // 무리수에 가까운 간격으로 소수부를 고르게 훑는다
            let requestedHeight = heightMM
            let appliedHeight = aligning
                ? SANEBackend.epson2AlignedHeightMM(
                    originYMM: originYMM,
                    heightMM: requestedHeight,
                    range: ScannerOptionRange(minimum: 0, maximum: 300, step: nil),
                    surfaceBottomMM: 300
                )
                : requestedHeight
            let output = Self.epson2OutputPixels(
                originXMM: 0,
                originYMM: originYMM,
                widthMM: widthMM,
                heightMM: appliedHeight,
                dpi: dpi
            )
            if Self.aspectMismatches(
                width: output.width,
                height: output.height,
                widthMM: widthMM,
                heightMM: appliedHeight
            ) {
                mismatches += 1
            }
            let expectedLines = appliedHeight / Self.millimetersPerInch * Double(dpi)
            worstLoss = max(worstLoss, (expectedLines - Double(output.height)) / expectedLines)
            worstGrowth = max(worstGrowth, appliedHeight - requestedHeight)
        }
        return (Double(mismatches) / Double(samples), worstLoss, worstGrowth)
    }

    /// 정렬이 없으면 작은 컷일수록 세로가 크게 잘리고 종횡비 검사가 실제로 터진다.
    func testUnalignedHeightLosesLinesOnSmallFrames() {
        let frame35mm = sweep(widthMM: 36, heightMM: 24, dpi: 3200, aligning: false)
        XCTAssertGreaterThan(
            frame35mm.mismatchRate, 0.2,
            "35mm 컷은 정렬 없이는 종횡비 검사가 자주 실패해야 한다(실측 재현)"
        )
        XCTAssertGreaterThan(
            frame35mm.worstHeightLoss, 0.03,
            "세로 손실이 3%를 넘어야 한다"
        )

        // 절삭량은 최대 1mm로 고정이므로, 프레임이 클수록 상대 손실이 줄어든다.
        let strip = sweep(widthMM: 56, heightMM: 220, dpi: 3200, aligning: false)
        XCTAssertLessThan(strip.worstHeightLoss, 0.006)
        XCTAssertEqual(strip.mismatchRate, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(
            frame35mm.worstHeightLoss, strip.worstHeightLoss * 5,
            "손실은 절대 오차이므로 작은 컷에서 훨씬 크게 나타난다"
        )
    }

    /// 정렬하면 절삭이 아무 일도 하지 않는다. 대가는 최대 1mm 확장뿐이고 잘림은 없다.
    func testAlignedHeightRemovesTruncation() {
        for (widthMM, heightMM) in [(36.0, 24.0), (56.0, 41.5), (41.5, 56.0), (56.0, 220.0)] {
            for dpi in [300, 1200, 3200, 6400] {
                let result = sweep(
                    widthMM: widthMM,
                    heightMM: heightMM,
                    dpi: dpi,
                    aligning: true
                )
                XCTAssertEqual(
                    result.mismatchRate, 0, accuracy: 1e-9,
                    "\(widthMM)x\(heightMM)mm @\(dpi)dpi 정렬 후에는 종횡비가 어긋나면 안 된다"
                )
                XCTAssertLessThan(
                    result.worstHeightLoss, 0.005,
                    "\(widthMM)x\(heightMM)mm @\(dpi)dpi 정렬 후 세로 손실은 반올림 수준이어야 한다"
                )
                XCTAssertLessThanOrEqual(
                    result.worstGrowthMM, 1.0 + 1e-9,
                    "정렬 확장은 1mm를 넘지 않는다"
                )
            }
        }
    }

    // MARK: 정렬 헬퍼 자체의 경계 동작

    private let openRange = ScannerOptionRange(minimum: 0, maximum: 300, step: nil)

    func testAlignmentGrowsToNextWholeMillimeter() {
        let aligned = SANEBackend.epson2AlignedHeightMM(
            originYMM: 20.3,
            heightMM: 41.5,
            range: openRange,
            surfaceBottomMM: 300
        )
        XCTAssertEqual(20.3 + aligned, 62, accuracy: 1e-9)
        XCTAssertGreaterThan(aligned, 41.5, "확장 방향이어야 이미지가 잘리지 않는다")
    }

    func testAlignmentLeavesWholeMillimeterBottomUntouched() {
        let aligned = SANEBackend.epson2AlignedHeightMM(
            originYMM: 20,
            heightMM: 42,
            range: openRange,
            surfaceBottomMM: 300
        )
        XCTAssertEqual(aligned, 42, accuracy: 1e-12)
    }

    /// 아래쪽 경계에 붙어 있으면 확장할 수 없으므로 내려서 맞춘다.
    func testAlignmentShrinksWhenGrowingWouldLeaveTheScanSurface() {
        let aligned = SANEBackend.epson2AlignedHeightMM(
            originYMM: 250.4,
            heightMM: 49.2,
            range: openRange,
            surfaceBottomMM: 299.8
        )
        XCTAssertEqual(250.4 + aligned, 299, accuracy: 1e-9)
        XCTAssertLessThan(aligned, 49.2)
    }

    /// 범위가 정렬값을 받아주지 못하면 요청값을 그대로 둔다(무리하게 바꾸지 않는다).
    func testAlignmentFallsBackToRequestWhenRangeRejectsBothDirections() {
        let quantized = ScannerOptionRange(minimum: 0, maximum: 300, step: 41.5)
        let aligned = SANEBackend.epson2AlignedHeightMM(
            originYMM: 20.3,
            heightMM: 41.5,
            range: quantized,
            surfaceBottomMM: 300
        )
        XCTAssertEqual(aligned, 41.5, accuracy: 1e-12)
    }

    func testAlignmentIgnoresNonFiniteAndNonPositiveInput() {
        XCTAssertEqual(
            SANEBackend.epson2AlignedHeightMM(
                originYMM: .nan, heightMM: 41.5, range: openRange, surfaceBottomMM: 300
            ),
            41.5,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            SANEBackend.epson2AlignedHeightMM(
                originYMM: 20.3, heightMM: 0, range: openRange, surfaceBottomMM: 300
            ),
            0,
            accuracy: 1e-12
        )
    }
}
