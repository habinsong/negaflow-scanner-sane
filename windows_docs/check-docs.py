#!/usr/bin/env python3
"""windows_docs 정합성 검사.

문서가 서로 어긋나는 것을 막는다. 의존성 없음, 표준 라이브러리만 쓴다.

    python3 windows_docs/check-docs.py

검사 항목:
  1. 상대 링크가 실제 파일을 가리키는가
  2. `[문서](경로.md) §N.M` 의 섹션 번호가 그 문서에 존재하는가
  3. D-nn 이 decision-register 에 등록돼 있는가
  4. Q-nn 이 open-questions 에 정의돼 있는가
  5. I-nn 이 product-invariants 에 정의돼 있는가
  6. spike ID 가 결과 표와 본문 양쪽에 있는가
  7. 어느 문서에서도 링크되지 않은 고아 문서가 있는가
  8. 문서 첫머리에 기준일/상태가 있는가
  9. 본체 저장소를 §N 으로 인용할 때 파일명을 명시했는가
 10. 표에 인용된 .swift 행수가 실제 파일과 맞는가

실패하면 exit 1. CI 에 붙일 수 있다.

이 스크립트가 잡지 못하는 것: 내용이 코드와 맞는지.
그건 사람이 소스를 읽어야 한다 — 실제로 그렇게 해서
[[field-lessons]] §9b 를 찾았다.
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.abspath(__file__))
SKIP_ORPHAN = {"README.md"}


def md_files():
    for dirpath, _, names in os.walk(ROOT):
        for n in sorted(names):
            if n.endswith(".md"):
                # 문서 안의 링크는 언제나 `/` 를 쓴다. Windows 의 `\` 를 그대로
                # 흘리면 이 스크립트의 모든 경로 비교가 어긋나고, 결과는
                # "파일이 없다"라는 엉뚱한 실패가 된다.
                relative = os.path.relpath(os.path.join(dirpath, n), ROOT)
                yield relative.replace(os.sep, "/")


def normalized(base, link):
    """문서 링크를 저장소 상대 경로로. **구분자는 언제나 슬래시다.**

    os.path.normpath 는 Windows 에서 역슬래시를 내므로 md_files() 의 키와
    어긋난다. 그러면 링크가 전부 "없는 파일"로 보이고, 실제 원인과 아무
    관계 없는 실패가 44건 쏟아진다.
    """
    return os.path.normpath(os.path.join(base, link)).replace(os.sep, "/")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def section_numbers(text):
    return {m.group(1) for m in re.finditer(r"^#{2,4}\s+(\d+(?:\.\d+)*[a-z]?)\.?\s", text, re.M)}


def has_section(sections, wanted):
    return any(s == wanted or s.startswith(wanted + ".") for s in sections)


def main():
    files = list(md_files())
    text = {f: read(f) for f in files}
    sections = {f: section_numbers(t) for f, t in text.items()}
    problems = []
    linked = set()

    # 1 & 2 — 링크와 섹션 참조
    for f, t in text.items():
        base = os.path.dirname(f)
        for m in re.finditer(r"\]\(([^)#]+\.md)(#[^)]*)?\)", t):
            target = normalized(base, m.group(1))
            linked.add(target)
            # windows_docs 밖(예: sane-runtime/SOURCES.md)을 가리키는 링크는
            # text 에 없다. 그건 깨진 링크가 아니라 이 스크립트의 범위 밖일
            # 뿐이므로, 파일이 실재하는지만 확인한다.
            if target not in text and not os.path.isfile(os.path.join(ROOT, target)):
                problems.append(f"{f}: 링크가 없는 파일을 가리킨다 -> {m.group(1)}")
        for m in re.finditer(r"\]\(([^)#]+\.md)\)[^\n]{0,14}?§\s*(\d+(?:\.\d+)*)", t):
            target = normalized(base, m.group(1))
            if target in sections and not has_section(sections[target], m.group(2)):
                problems.append(
                    f"{f}: {m.group(1)} 에 §{m.group(2)} 가 없다"
                )

    # 3~5 — ID 정의처
    registries = [
        ("D", r"\bD-(\d{2})\b", "00-overview/decision-register.md", r"^\|\s*D-(\d{2})\s*\|"),
        ("Q", r"\bQ-(\d{1,2})\b", "99-plan/open-questions.md", r"^(?:##\s+|\|\s*)Q-(\d{1,2})[.\s]"),
        ("I", r"\bI-(\d{1,2})\b", "99-plan/product-invariants.md", r"^##\s+I-(\d{1,2})\."),
    ]
    for label, use_pat, home, def_pat in registries:
        if home not in text:
            problems.append(f"{home} 가 없다 ({label}-nn 정의처)")
            continue
        defined = set(re.findall(def_pat, text[home], re.M))
        used = defaultdict(set)
        for f, t in text.items():
            if f == home:
                continue
            for n in re.findall(use_pat, t):
                used[n].add(f)
        for n in sorted(used, key=int):
            if n not in defined:
                where = ", ".join(sorted(used[n])[:3])
                problems.append(f"{label}-{n} 이 {home} 에 없다 (사용: {where})")

    # 6 — spike ID
    spike = "99-plan/spike-checklist.md"
    if spike in text and "## 결과 표" in text[spike]:
        body, results = text[spike].split("## 결과 표", 1)
        pat = r"\b([A-Z]{1,2}-\d+[a-z]?)\b"
        in_body = set(re.findall(pat, body)) - {"LS-50"}
        in_body -= set(re.findall(r"\bD-\d{2}\b", body))  # 결정 참조는 spike 가 아니다
        in_res = set(re.findall(r"\|\s*([A-Z]{1,2}-\d+[a-z]?)\s*\|", results))
        for s in sorted(in_res - in_body):
            problems.append(f"{spike}: {s} 가 결과 표에만 있고 본문 설명이 없다")
        for s in sorted(in_body - in_res):
            problems.append(f"{spike}: {s} 가 본문에만 있고 결과 표에 없다")

    # 9 — 본체 저장소 인용은 파일을 명시한다
    #     check-docs.py 는 다른 저장소를 열지 못하므로 링크 검사가 통하지 않는다.
    #     최소한 "어느 문서의 §N 인지"는 적혀 있어야 독자가 찾아갈 수 있다.
    #     (본체 README 에도 §6 이 있고 plugin-architecture.md 에도 §6 이 있다.)
    for f, t in text.items():
        for m in re.finditer(r"본체[^\n]{0,70}?§\s*\d", t):
            span = m.group(0)
            if "README" in span or re.search(r"`[^`]+\.md`", span):
                continue
            problems.append(
                f"{f}: 본체 저장소 인용에 파일명이 없다 -> {span.strip()!r}"
            )

    # 10 — 인용된 소스 행수가 실제와 맞는가
    #      macos-inventory 의 파일별 행수는 이식 규모 산정의 근거다.
    #      코드가 바뀌면 조용히 낡는다(실제로 2026-08-04 에 헤더 합계 두 개가 낡아 있었다).
    repo = os.path.dirname(ROOT)
    swift = {}
    for sub in ("Sources", "Tests"):
        base = os.path.join(repo, sub)
        for dirpath, _, names in os.walk(base):
            for n in names:
                if n.endswith(".swift"):
                    swift.setdefault(n, os.path.join(dirpath, n))
    if swift:
        for f, t in text.items():
            for m in re.finditer(r"^\|\s*`([\w+.-]+\.swift)`\s*\|\s*([\d,]+)\s*\|", t, re.M):
                name, claimed = m.group(1), int(m.group(2).replace(",", ""))
                path = swift.get(name)
                if path is None:
                    problems.append(f"{f}: 표에 있는 `{name}` 가 저장소에 없다")
                    continue
                with open(path, encoding="utf-8") as fh:
                    actual = sum(1 for _ in fh)
                if actual != claimed:
                    problems.append(
                        f"{f}: `{name}` 행수가 낡았다 — 문서 {claimed}, 실제 {actual}"
                    )

    # 7 — 고아 문서
    for f in files:
        if f not in linked and f not in SKIP_ORPHAN:
            problems.append(f"{f}: 어느 문서에서도 링크되지 않는다")

    # 8 — 머리말
    for f in files:
        if f in SKIP_ORPHAN:
            continue
        head = "\n".join(text[f].splitlines()[:8])
        if "기준일:" not in head:
            problems.append(f"{f}: 머리말에 '기준일:' 이 없다")
        if "상태:" not in head:
            problems.append(f"{f}: 머리말에 '상태:' 가 없다")

    if problems:
        print(f"문서 검사 실패 — {len(problems)}건\n")
        for p in problems:
            print("  " + p)
        return 1

    print(f"문서 검사 통과 — {len(files)}개 문서")
    return 0


if __name__ == "__main__":
    sys.exit(main())
