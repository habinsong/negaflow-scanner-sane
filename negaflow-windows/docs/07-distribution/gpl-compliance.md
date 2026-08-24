# Windows 배포물과 GPL 자료

기준일: 2026-08-25

Windows SANE 어댑터와 bundled SANE runtime은 GPL-2.0-or-later 배포물입니다. Negaflow 본체와는 별도 프로세스·별도 설치물로 유지합니다.

현재 설치 파일에는 다음 자료가 있어야 합니다.

- GPL 전문과 제3자 고지
- 사용한 SANE runtime과 어댑터의 대응 소스 archive
- `manifest.json`, adapter 실행 파일, bundled `scanimage.exe`

현재 SANE 1.4.0 runtime은 `PKGBUILD`와 001~011 패치로 재현합니다. 009 epson2 IR,
010 설치 번들 backend 경로, 011 OpticFilm host-side Gray도 기존 패치와 동일하게
GPL-2.0-or-later 대응 소스에 포함합니다. 2026-08-25 clean 작업 디렉터리에서
`scripts/build-sane-runtime.ps1`이 원본 tarball 해시와 11개 패치 입력을 통과했습니다.

> **미해결 — 릴리스 차단.** 패치 `010`·`011`이 아직 git 에 추적되지 않았습니다. 대응 소스는
> 커밋된 트리에서 나와야 하므로, 두 패치와 `.gitattributes` 경로 수정·PKGBUILD 고정 해시
> 복원을 커밋하기 전에는 이 runtime 을 배포할 수 없습니다. 커밋 뒤 같은 소스에서 다시 빌드한
> 해시로 `windows-build-and-install.md` §7 을 갱신합니다.

패치 파일의 줄바꿈은 LF 여야 합니다. 저장소 루트 `.gitattributes` 의 패턴이 실제 경로와
어긋나 001~009 가 CRLF 로 오염된 적이 있고, 그때 PKGBUILD 의 고정 sha256 이 오염된 파일의
해시로 바뀌었습니다. 고정 해시는 항상 커밋된 LF 파일 기준이어야 합니다.

`verify-installer.ps1`은 설치 뒤 위 payload의 존재, `manifest.json`, `detect`, 무인 제거를 확인합니다. 실제 장치 스캔과 코드 서명은 이 검사 범위에 들어가지 않습니다.

릴리스 전에 source archive가 실제 payload와 같은 버전인지, license·notice가 함께
들어 있는지 별도로 확인합니다. `make-payload.sh`의 adapter source archive는
`git archive HEAD`에서 생성되므로 dirty tree로 만든 로컬 시험 setup은 릴리스 대응
소스 일치 증거가 아닙니다. 최종 배포 setup은 커밋된 동일 소스에서 다시 만들고
archive와 바이너리 입력의 일치를 확인해야 합니다. 이 문서는 법률 자문이나 배포
적법성 판단을 대신하지 않습니다.
