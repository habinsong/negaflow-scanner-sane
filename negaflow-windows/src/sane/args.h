// negaflow-scanner-sane — Windows adapter
// sane/args — `scanimage` 획득 인자 생성.
//
// 이식 원본: Sources/SANEPluginCore/SANEBackend+ScanExecution.swift (makeScanimageArgs)
// 정본 문서: windows_docs/10-lessons/driver-option-reference.md §1
//
// **없는 옵션에는 플래그를 보내지 않는다.** coolscan3 에 `--mode` 를 넘기면
// scanimage 가 스캔을 시작하기도 전에 죽는다. MediaSelection 의 hasXxxOption
// 필드가 전부 존재하는 유일한 이유다.
//
// **인자 순서가 계약이다.** 골든 픽스처가 배열 순서까지 비교한다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <optional>
#include <string>
#include <vector>

#include "sane/media.h"

namespace negaflow::sane {

/// 획득 패스. IR 은 별도 패스로 한 번 더 돈다.
enum class AcquisitionPass { Main, Infrared };

/// 획득 인자를 만든다.
///
/// 순서:
///   -d <dev> -p
///   [--source S] [--mode M]
///   ─ main 패스만 ─
///   [--advance=no] [--color-correction C] [--gamma-correction G]
///   [--film-type|--type|--negative=…] [--brightness=] [--contrast=]
///   [--scan-exposure-time=] [--clean-image=yes] [--preview=yes]
///   ─ 공통 ─
///   [--resolution N] [--depth N]
///   [--tl-x --tl-y --br-x --br-y] 또는 [-l -t]
///   [-x -y]
///   --format=tiff
///
/// **IR 패스는 소스/모드만 바꾸고 해상도·심도·지오메트리를 본 스캔과 동일하게
/// 유지한다.** 먼지 맵을 RGB 에 정렬하려면 픽셀 격자가 같아야 한다 —
/// 최적화가 아니라 정확성 요건이다.
///
/// `brightnessOverride` 는 다중 노출 브래킷에서 패스별 밝기를 강제할 때 쓴다.
/// 값이 있으면 `options.brightnessAdjustment` 보다 우선한다.
[[nodiscard]] std::vector<std::string> makeScanimageArgs(
    std::string_view devname,
    const ScanOptions& options,
    const MediaSelection& media,
    AcquisitionPass pass = AcquisitionPass::Main,
    std::optional<int> brightnessOverride = std::nullopt);

}  // namespace negaflow::sane
