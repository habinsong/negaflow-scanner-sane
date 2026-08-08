// negaflow-scanner-sane — Windows adapter
// util/msvc_fp_contract — MSVC 에서 FMA 축약을 끈다.
//
// **이 헤더는 CMake 가 `/FI` 로 모든 번역 단위에 강제 포함한다.**
// 직접 `#include` 하지 않아도 된다 — 오히려 하지 않는 편이 낫다.
// 어느 파일이 "부동소수점에 민감한가"를 사람이 판단하게 두면 언젠가 틀린다.
//
// 정본 문서: docs/04-imaging/numerical-parity.md §5
//            docs/04-imaging/exposure-merge.md §7.4 (D-11)
//
// ## 왜 `/fp:precise` 만으로는 부족한가 — 2026-08-05 조사 결과
//
// CMakeLists 는 `/fp:precise` 를 걸면서 "기본이지만 명시한다"고 적고 있었다.
// **VS 2022 에서는 맞고 VS 2019 에서는 틀리다.**
//
// ```text
//                     /fp:precise 의 기본 fp_contract
// VS 2019 이하        on    ← 축약이 일어난다
// VS 2022 17.0+       off
// ```
//
// VS 2019 의 축약은 플랫폼마다 달랐다(MSVC 팀 블로그, "The /fp:contract flag
// and changes to FP modes in VS2022"):
//
// ```text
// ARM64        스칼라와 벡터 FMA 를 **둘 다** 낸다. /arch 플래그가 필요 없다
//              (FMADD 가 armv8.0-A 기본이다)
// x64          벡터 FMA 만. 단 /arch:AVX2 이상이어야 한다
// ```
//
// 즉 **VS 2019 + ARM64 에서는 `a + b*c` 가 그냥 FMA 가 된다.** `imaging/align`
// 과 `imaging/merge` 가 정확히 그 형태의 식을 쓴다. 중간 반올림이 사라지므로
// 정확도는 올라가고 **결과는 macOS 와 달라진다.** D-11 이 금지하는 것이 그것이다.
//
// 이것은 새로운 함정이 아니라 **이미 한 번 밟은 함정의 반대편이다.**
// 파리티 스크립트가 `-ffp-contract=off` 없이 컴파일해 1 ULP 로 터진 적이 있다
// ([field-lessons](../../docs/10-lessons/field-lessons.md) §9b.2).
// 그때는 clang 이었고 이번엔 MSVC 다.
//
// ## 왜 `#pragma fp_contract(off)` 인가
//
// **`/fp:contract-` 라는 플래그는 존재하지 않는다.** `/fp:contract` 는 켜는
// 쪽만 있고 끄는 형태가 없다(`/fp:except[-]` 와 달리 `[-]` 가 없다).
// `/fp:strict` 도 축약을 끄지만 `/fp:except` 와 `fenv_access` 까지 켜서
// 최적화를 광범위하게 막는다 — 필요 없는 대가다.
//
// `#pragma fp_contract(off)` 는 **VS 2019 와 VS 2022 양쪽에서, x64 와 ARM64
// 양쪽에서 통하는 유일한 수단**이다. MSVC 문서의 예제가 `/O2 /fp:fast
// /arch:AVX2` 로 컴파일해도 FMA 가 나오지 않음을 보인다 — `/fp:fast` 보다 세다.
//
// `#pragma float_control(precise, on)` 은 **VS 2019 에서 축약에 영향을 주지
// 않는다.** 그것으로 대신하지 않는다.
//
// ## 남는 것 — 이것으로도 비트 동일이 보장되지는 않는다
//
// ```text
// std::fma 를 **직접 부르면** 그대로 FMA 명령이 나온다   양쪽 다 그러므로 문제없다
// sin/cos/pow/exp/log 는 어느 libm 도 정확 반올림이 아니다  마지막 ulp 가 갈린다
// long double 폭이 다르다                                   우리는 쓰지 않는다
// ```
//
// 이 계층이 쓰는 것은 `+ - * / sqrt` 뿐이고 그것들은 IEEE-754 가 정확히
// 규정한다. 초월함수를 쓰기 시작하면 위 표를 다시 읽는다.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#if defined(_MSC_VER) && !defined(__clang__)
// 함수 안에서는 쓸 수 없다. 번역 단위 맨 앞이어야 하고, `/FI` 가 그것을 보장한다.
#pragma fp_contract(off)
#endif
