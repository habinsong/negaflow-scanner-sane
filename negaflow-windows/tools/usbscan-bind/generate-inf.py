#!/usr/bin/env python3
"""negaflow-usbscan.inf 를 SANE 자신의 기기표에서 만든다.

왜 생성하는가
    INF 는 하드웨어 ID 로 맞물리므로 목록이 있어야 한다. 그 목록을 손으로 적으면 두 가지가
    같이 틀어진다 — 우리가 지원한다고 적은 기종과 SANE 이 실제로 아는 기종. 그래서 SANE
    upstream 의 `doc/descriptions/*.desc` 를 그대로 읽는다. 거기 `:usbid` 로 적힌 것이
    백엔드가 여는 기기의 정의다.

무엇을 만드는가
    우리가 배포하는 백엔드(dll.conf 에 있는 것)만 대상으로 한다. 없는 백엔드의 기기를
    usbscan 에 묶으면 열리지도 않을 장치를 우리 이름으로 잡는 꼴이 된다.

    그 안에서도 **필름을 스캔할 수 있는 기종만** 넣는다(FILM_MODELS). 이 INF 는 장치의
    원래 드라이버를 밀어낼 수 있다. 프린터 복합기는 USB 복합 장치라 부모 장치가
    `USB\\VID_…&PID_…` 하드웨어 ID 를 갖고, 원래 드라이버 usbccgp 는 호환 ID 로 잡혀
    있다. 하드웨어 ID 로 맞물리는 이 INF 가 이기면 부모가 usbscan 에 묶이고 그 아래
    인쇄·스캔·카드 리더 인터페이스가 통째로 사라진다. 필름을 못 읽는 기기는 이 플러그인이
    쓸 일이 없으므로 처음부터 넣지 않는다. desc 가 `:unsupported` 로 적은 기종도 뺀다 —
    우리 백엔드가 열지 못하는 기기의 드라이버를 바꿀 이유가 없다.

쓰는 법
    py generate-inf.py                 # gitlab 에서 받아 생성
    py generate-inf.py --source <dir>  # 받아 둔 sane-backends 체크아웃에서 생성

    결과는 커밋한다. 설치할 때 네트워크를 타지 않는다.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import urllib.request

RAW = "https://gitlab.com/sane-project/backends/-/raw/master/doc/descriptions/"

# dll.conf 에 있는 것과 같아야 한다. 늘리려면 백엔드부터 배포에 넣는다.
BACKENDS = ("genesys", "epson2", "epsonds", "coolscan2", "coolscan3")

# 필름을 스캔할 수 있는 기종만 받는다(모델 이름 기준, 위 설명 참조).
FILM_MODELS: dict[str, re.Pattern[str]] = {
    # genesys 가 투과(TRANSPARENCY) 스캔 방식을 정의한 기종: OpticFilm 전부와 필름
    # 어댑터가 있는 CanoScan 네 종. LiDE·OpticBook·문서 스캐너는 평판뿐이다
    # (backend/genesys/tables_model.cpp 의 model.resolutions).
    "genesys": re.compile(r"^(OpticFilm\b|CanoScan (4400F|5600F|8400F|8600F)$)"),
    # 투과 유닛이 있는 Perfection(이름 끝이 PHOTO/Photo/Pro)과 그 일본 이름인 GT-X,
    # 투과 유닛을 달 수 있는 Expression. 복합기가 아니라 부모 장치를 밀어낼 일이 없다.
    # V600·V550·V500 처럼 epson2 가 :unsupported 로 적은 기종은 상태 검사에서 빠진다.
    "epson2": re.compile(r"^(Perfection .* (PHOTO|Photo|Pro)|GT-X\d+|Expression .+)$"),
    # 투과 유닛이 있는 기종이 없다. 복합기와 문서 스캐너뿐이다.
    "epsonds": re.compile(r"(?!)"),
    # Nikon Coolscan 은 전부 필름 스캐너다.
    "coolscan2": re.compile(r""),
    "coolscan3": re.compile(r""),
}

MODEL_PATTERN = re.compile(r':model\s+"([^"]+)"')
USBID_PATTERN = re.compile(r':usbid\s+"(0x[0-9a-fA-F]{4})"\s+"(0x[0-9a-fA-F]{4})"')
MFG_PATTERN = re.compile(r':mfg\s+"([^"]+)"')
STATUS_PATTERN = re.compile(r':status\s+:(\w+)')


def read_desc(backend: str, source: pathlib.Path | None) -> str:
    if source is not None:
        path = source / "doc" / "descriptions" / f"{backend}.desc"
        return path.read_text(encoding="utf-8", errors="replace")
    with urllib.request.urlopen(RAW + f"{backend}.desc", timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def parse(text: str) -> list[tuple[str, str, str, str, str]]:
    """(vid, pid, 제조사, 모델, 상태) 를 문서 순서대로 뽑는다.

    `.desc` 는 `:mfg` 아래에 `:model` 이 오고, 그 모델의 `:usbid` 와 `:status` 가 다음
    `:model` 이나 `:mfg` 전까지 이어진다. `:status` 가 `:usbid` 보다 뒤에 오기도 하므로
    모델 단위로 모은 뒤에 짝을 짓는다.
    """
    entries: list[tuple[str, str, str, str, str]] = []
    mfg = ""
    # [제조사, 모델, [(vid, pid)], 상태]
    current: list | None = None

    def flush() -> None:
        if current is None:
            return
        for vid, pid in current[2]:
            entries.append((vid, pid, current[0], current[1], current[3]))

    for line in text.splitlines():
        if (found := MFG_PATTERN.search(line)) is not None:
            flush()
            current = None
            mfg = found.group(1).strip()
        elif (found := MODEL_PATTERN.search(line)) is not None:
            flush()
            current = [mfg, found.group(1).strip(), [], ""]
        elif current is not None and (found := USBID_PATTERN.search(line)) is not None:
            current[2].append((found.group(1)[2:].upper(), found.group(2)[2:].upper()))
        elif current is not None and (found := STATUS_PATTERN.search(line)) is not None:
            current[3] = found.group(1)
    flush()
    return entries


def sanitise(text: str) -> str:
    # INF 문자열은 큰따옴표와 퍼센트를 담을 수 없다. 이름은 사람이 읽는 용도라 다듬어도 된다.
    return text.replace('"', "").replace("%", " pct ").strip() or "Scanner"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("negaflow-usbscan.inf"),
    )
    arguments = parser.parse_args()

    # 같은 기기가 여러 백엔드에 적히기도 한다. INF 에 같은 하드웨어 ID 를 두 번 적으면
    # 설치가 거부되므로 처음 본 것만 남긴다.
    seen: dict[tuple[str, str], tuple[str, str, str]] = {}
    counts: dict[str, int] = {}
    for backend in BACKENDS:
        entries = parse(read_desc(backend, arguments.source))
        added = 0
        for vid, pid, mfg, model, status in entries:
            if status == "unsupported" or not FILM_MODELS[backend].search(model):
                continue
            if (vid, pid) in seen:
                # 같은 ID 에 일본 이름(GT-X900)과 해외 이름(Perfection V700 Photo)이 함께
                # 적혀 있으면 장치 관리자에서 알아보기 쉬운 Perfection 이름을 쓴다.
                known_backend, known_mfg, known_model = seen[(vid, pid)]
                if (known_backend == backend and model.startswith("Perfection")
                        and not known_model.startswith("Perfection")):
                    seen[(vid, pid)] = (backend, known_mfg, model)
                continue
            seen[(vid, pid)] = (backend, mfg, model)
            added += 1
        counts[backend] = added
        print(f"  {backend:10s} {added:4d} devices", file=sys.stderr)

    # 제조사별로 묶는다. INF 의 [Manufacturer] 는 그 단위로 적는다.
    vendors: dict[str, list[tuple[str, str, str, str]]] = {}
    for (vid, pid), (backend, mfg, model) in sorted(seen.items()):
        vendors.setdefault(sanitise(mfg) or "Scanner", []).append((vid, pid, model, backend))

    symbols: dict[str, str] = {}
    lines: list[str] = []
    manufacturers: list[str] = []
    sections: list[str] = []

    for index, (vendor, devices) in enumerate(sorted(vendors.items())):
        vendor_symbol = f"Vendor{index:02d}"
        symbols[vendor_symbol] = vendor
        manufacturers.append(f"%{vendor_symbol}% = {vendor_symbol}.Models, NTamd64, NTarm64")
        for architecture in ("NTamd64", "NTarm64"):
            body = [f"[{vendor_symbol}.Models.{architecture}]"]
            for order, (vid, pid, model, backend) in enumerate(devices):
                name_symbol = f"{vendor_symbol}Dev{order:03d}"
                symbols[name_symbol] = f"{sanitise(model)} (negaflow, {backend})"
                body.append(
                    f"%{name_symbol}% = Negaflow.UsbScan, USB\\VID_{vid}&PID_{pid}")
            sections.append("\n".join(body))

    lines.append(HEADER.format(count=len(seen), backends=", ".join(BACKENDS)))
    lines.append("[Manufacturer]")
    lines.extend(manufacturers)
    lines.append("")
    lines.extend(section + "\n" for section in sections)
    lines.append(INSTALL_SECTION)
    lines.append("[Strings]")
    lines.append('Provider = "negaflow-scanner-sane"')
    lines.extend(f'{symbol} = "{value}"' for symbol, value in symbols.items())

    arguments.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{arguments.output}: {len(seen)} devices", file=sys.stderr)
    return 0


HEADER = """\
; negaflow-usbscan.inf — 스캐너를 Windows 자신의 usbscan.sys 에 붙인다
;
; **이 파일은 생성물이다. 손으로 고치지 말고 generate-inf.py 를 다시 돌린다.**
; 기기 목록은 SANE upstream 의 doc/descriptions/*.desc 에서 나온다 — 백엔드가 실제로
; 아는 기기 가운데 **필름을 스캔할 수 있는 기종만** 넣는다. {count}개 기기, 백엔드:
; {backends}.
;
; 프린터 복합기와 문서 스캐너는 넣지 않는다. 복합기는 USB 복합 장치라, 이 INF 가 부모
; 장치에 붙으면 원래 드라이버 usbccgp 를 밀어내고 인쇄·스캔 인터페이스가 통째로 사라진다.
;
; 왜 필요한가
;   sanei_usb 의 Windows 경로(patch 005)는 still-image 클래스 드라이버 usbscan.sys 가
;   열어주는 raw USB 통로로 장치와 이야기한다. 그 통로가 생기려면 장치가 usbscan 서비스에
;   묶여 있어야 하고, 묶는 일은 INF 만 할 수 있다. 벤더 소프트웨어가 없는 기기에서는
;   스캐너가 CM_PROB_FAILED_INSTALL(코드 28) 로 남고 SANE 은 "스캐너 없음" 만 말한다.
;
; 무엇을 설치하는가
;   **아무 바이너리도 설치하지 않는다.** Include=sti.inf / Needs=STI.USBSection 으로
;   Windows 가 이미 갖고 있는 usbscan.sys 를 가리킬 뿐이다. 다만 같은 하드웨어 ID 를
;   가진 기기의 드라이버는 Windows 의 순위 규칙에 따라 이것으로 바뀔 수 있다. 목록을
;   필름 스캐너로 좁힌 이유가 그것이다.

[Version]
Signature   = "$Windows NT$"
Class       = Image
ClassGUID   = {{6bdd1fc6-810f-11d0-bec7-08002be2092f}}
Provider    = %Provider%
DriverVer   = 08/14/2026,1.0.0.0
; 카탈로그는 install.ps1 이 자체 서명으로 만든다. 서명 없는 INF 는 pnputil 이 거부한다.
CatalogFile = negaflow-usbscan.cat
"""

INSTALL_SECTION = """\
[Negaflow.UsbScan]
Include       = sti.inf
Needs         = STI.USBSection
SubClass      = StillImage
DeviceType    = 1
DeviceSubType = 0x0
Capabilities  = 0x00000031

[Negaflow.UsbScan.Services]
Include = sti.inf
Needs   = STI.USBSection.Services
"""


if __name__ == "__main__":
    raise SystemExit(main())
