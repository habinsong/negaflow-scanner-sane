// SPDX-License-Identifier: GPL-2.0-or-later

#include "sane/args.h"

#include "sane/device_list.h"
#include "util/numeric.h"

namespace negaflow::sane {

std::vector<std::string> makeScanimageArgs(std::string_view devname,
                                           const ScanOptions& options,
                                           const MediaSelection& media,
                                           AcquisitionPass pass,
                                           std::optional<int> brightnessOverride) {
    std::vector<std::string> args{"-d", std::string(devname), "-p"};

    std::optional<std::string> mode = media.mode;
    std::optional<std::string> source = media.source;

    if (pass == AcquisitionPass::Infrared) {
        switch (media.irStrategy.kind) {
            case IRStrategy::Kind::SeparateSource:
                source = media.irStrategy.value;
                // IR 패스는 Gray 로 찍는다. irPassMode 가 없으면 본 스캔 모드를 쓴다.
                mode = media.irPassMode.has_value() ? media.irPassMode : media.mode;
                break;
            case IRStrategy::Kind::SeparateMode:
                mode = media.irStrategy.value;
                break;
            case IRStrategy::Kind::None:
            case IRStrategy::Kind::CleanImage:
                break;
        }
    }

    if (source.has_value()) {
        args.emplace_back("--source");
        args.push_back(*source);
    }
    if (mode.has_value()) {
        args.emplace_back("--mode");
        args.push_back(*mode);
    }

    std::string scannerID = options.scannerID;
    if (scannerID.rfind("sane-", 0) == 0) scannerID.erase(0, 5);
    const std::string backend = backendName(scannerID);

    // 감마 테이블과 초점은 **두 패스 모두** 같아야 한다. IR 채널은 그림이 아니라 측정값이다.
    //
    // 감마: GT-X900 실측에서 IR 패스를 장치 기본 감마로 찍으면 신호가 전부 흰쪽 끝에 몰린다 —
    // 프레임의 2~3.4% 가 65535 에 그대로 잘리고 21~55% 가 65000 위에 뭉친다. 결함 신호는 필름
    // 베이스 바로 아래에 있는데 그 구간이 압축·절단되는 것이다. 같은 자리를 선형 테이블로 찍으면
    // 필름 베이스가 0.81 에 앉고 잘림이 없다.
    //
    // 초점: 두 패스의 초점면이 다르면 배율이 달라져 결함 지도가 결함에서 몇 px 옆에 놓인다.
    // 그러면 복원이 멀쩡한 필름을 덮고 결함은 남는다.
    if (backend == "epson2" && media.hasGammaCorrectionOption &&
        media.gammaCorrection.has_value()) {
        args.emplace_back("--gamma-correction");
        args.push_back(*media.gammaCorrection);
    }

    // 초점은 요청이 있을 때만 보낸다. 지정하지 않으면 장치 기본값이 그대로 쓰인다.
    // autofocus 와 focus 를 함께 보내면 장치가 어느 쪽을 따르는지 보장할 수 없어 갈라 둔다.
    if (options.autofocus.value_or(false) && media.hasAutofocusOption) {
        args.emplace_back("--autofocus=yes");
    } else if (options.focusPosition.has_value() && media.focusRange.has_value()) {
        args.emplace_back("--focus=" + std::to_string(*options.focusPosition));
        if (media.hasAutofocusOption) args.emplace_back("--autofocus=no");
    }

    if (pass == AcquisitionPass::Main) {

        // pieusb: full scan 뒤 다음 슬라이드로 이동하는 --advance 기본값이 yes 다.
        // 앱이 배치 이동을 요청한 적이 없으므로 확인되면 **항상 no**.
        if (backend == "pieusb" && media.hasAdvanceOption) {
            args.emplace_back("--advance=no");
        }

        // epson2: 장치 내부 색 처리를 끈다. negaflow 가 원본 밀도를 현상한다.
        // 감마는 위에서 두 패스 모두에 이미 붙였다 — 그림 쪽 제어만 여기 남는다.
        if (backend == "epson2" && media.hasColorCorrectionOption &&
            media.colorCorrection.has_value()) {
            args.emplace_back("--color-correction");
            args.push_back(*media.colorCorrection);
        }

        // 필름 극성. bool 옵션(--negative)은 `=값` 형태, enum 은 분리 인자.
        if (media.filmType.has_value() && media.filmTypeOptionName.has_value()) {
            if (*media.filmTypeOptionName == "negative") {
                args.emplace_back("--negative=" + *media.filmType);
            } else {
                args.emplace_back("--" + *media.filmTypeOptionName);
                args.push_back(*media.filmType);
            }
        }

        if (media.hasBrightnessOption) {
            if (brightnessOverride.has_value()) {
                // 다중 노출 브래킷의 패스별 밝기(정수).
                args.emplace_back("--brightness=" + std::to_string(*brightnessOverride));
            } else if (options.brightnessAdjustment.has_value()) {
                args.emplace_back("--brightness=" +
                                  util::saneNumber(*options.brightnessAdjustment));
            }
        }
        if (media.hasContrastOption && options.contrastAdjustment.has_value()) {
            args.emplace_back("--contrast=" + util::saneNumber(*options.contrastAdjustment));
        }
        if (media.hasScanExposureOption && options.hardwareExposureTime.has_value()) {
            args.emplace_back("--scan-exposure-time=" +
                              std::to_string(*options.hardwareExposureTime));
        }

        // 도달 불가 경로 — resolveMedia 가 CleanImage 를 만들지 않는다.
        // 분기는 원본과 함께 유지하되 **연결하지 않는다**(porting-map §3.5).
        if (media.irStrategy.kind == IRStrategy::Kind::CleanImage) {
            args.emplace_back("--" + media.irStrategy.value + "=yes");
        }

        if (options.resolutionDPI == 0 && media.hasPreviewOption) {
            args.emplace_back("--preview=yes");
        }
    }

    if (media.resolvedDPI.has_value()) {
        args.emplace_back("--resolution");
        args.emplace_back(std::to_string(*media.resolvedDPI));
    }
    if (media.depthArgument.has_value()) {
        args.emplace_back("--depth");
        args.emplace_back(std::to_string(*media.depthArgument));
    }

    // 지오메트리 — 세 형태가 배타적이다.
    if (media.usesCornerPixelGeometry && media.originXPixels.has_value() &&
        media.originYPixels.has_value() && media.rightPixels.has_value() &&
        media.bottomPixels.has_value()) {
        args.emplace_back("--tl-x");
        args.emplace_back(std::to_string(*media.originXPixels));
        args.emplace_back("--tl-y");
        args.emplace_back(std::to_string(*media.originYPixels));
        args.emplace_back("--br-x");
        args.emplace_back(std::to_string(*media.rightPixels));
        args.emplace_back("--br-y");
        args.emplace_back(std::to_string(*media.bottomPixels));
    } else if (media.originXMM.has_value() && media.originYMM.has_value()) {
        args.emplace_back("-l");
        args.emplace_back(util::saneNumber(*media.originXMM));
        args.emplace_back("-t");
        args.emplace_back(util::saneNumber(*media.originYMM));
    } else if (media.originXPixels.has_value() && media.originYPixels.has_value()) {
        args.emplace_back("-l");
        args.emplace_back(std::to_string(*media.originXPixels));
        args.emplace_back("-t");
        args.emplace_back(std::to_string(*media.originYPixels));
    }

    if (media.widthMM.has_value() && media.heightMM.has_value()) {
        args.emplace_back("-x");
        args.emplace_back(util::saneNumber(*media.widthMM));
        args.emplace_back("-y");
        args.emplace_back(util::saneNumber(*media.heightMM));
    } else if (media.widthPixels.has_value() && media.heightPixels.has_value()) {
        args.emplace_back("-x");
        args.emplace_back(std::to_string(*media.widthPixels));
        args.emplace_back("-y");
        args.emplace_back(std::to_string(*media.heightPixels));
    }

    args.emplace_back("--format=tiff");
    return args;
}

}  // namespace negaflow::sane
