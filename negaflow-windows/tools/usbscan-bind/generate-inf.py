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

# 여는 통로만 만드는 INF 다. 필름 스캐너가 아닌 것까지 잡을 이유가 없으므로 백엔드 단위로
# 거른다 — epson2 는 평판 겸용이라 전 기종을 받고, 나머지는 필름 전용이다.
MODEL_PATTERN = re.compile(r':model\s+"([^"]+)"')
USBID_PATTERN = re.compile(r':usbid\s+"(0x[0-9a-fA-F]{4})"\s+"(0x[0-9a-fA-F]{4})"')
MFG_PATTERN = re.compile(r':mfg\s+"([^"]+)"')


def read_desc(backend: str, source: pathlib.Path | None) -> str:
    if source is not None:
        path = source / "doc" / "descriptions" / f"{backend}.desc"
        return path.read_text(encoding="utf-8", errors="replace")
    with urllib.request.urlopen(RAW + f"{backend}.desc", timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def parse(text: str) -> list[tuple[str, str, str, str]]:
    """(vid, pid, 제조사, 모델) 을 문서 순서대로 뽑는다.

    `.desc` 는 `:mfg` 아래에 `:model` 이 오고 그 아래에 `:usbid` 가 오는 구조다. 앞선
    이름을 들고 가다 usbid 를 만나면 짝을 짓는다. 이름이 없는 항목은 버리지 않고 백엔드
    이름으로 채운다 — 통로를 여는 것이 목적이지 이름이 목적이 아니다.
    """
    entries: list[tuple[str, str, str, str]] = []
    mfg = ""
    model = ""
    for line in text.splitlines():
        if (found := MFG_PATTERN.search(line)) is not None:
            mfg = found.group(1).strip()
            continue
        if (found := MODEL_PATTERN.search(line)) is not None:
            model = found.group(1).strip()
            continue
        if (found := USBID_PATTERN.search(line)) is not None:
            vid, pid = found.group(1)[2:].upper(), found.group(2)[2:].upper()
            entries.append((vid, pid, mfg, model))
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
        for vid, pid, mfg, model in entries:
            if (vid, pid) in seen:
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
; 아는 기기가 곧 우리가 통로를 열 기기다. {count}개 기기, 백엔드: {backends}.
;
; 왜 필요한가
;   sanei_usb 의 Windows 경로(patch 005)는 still-image 클래스 드라이버 usbscan.sys 가
;   열어주는 raw USB 통로로 장치와 이야기한다. 그 통로가 생기려면 장치가 usbscan 서비스에
;   묶여 있어야 하고, 묶는 일은 INF 만 할 수 있다. 벤더 소프트웨어가 없는 기기에서는
;   스캐너가 CM_PROB_FAILED_INSTALL(코드 28) 로 남고 SANE 은 "스캐너 없음" 만 말한다.
;
; 무엇을 설치하는가
;   **아무 바이너리도 설치하지 않는다.** Include=sti.inf / Needs=STI.USBSection 으로
;   Windows 가 이미 갖고 있는 usbscan.sys 를 가리킬 뿐이다. 벤더 스택을 밀어내지 않는다.

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
