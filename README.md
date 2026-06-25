# Reverse Proxy Tutorial (Portal Gateway Routing)

여러 개의 독립적인 웹앱을 **하나의 도메인** 아래로 모으는 **리버스 프록시 / 게이트웨이 라우팅** 패턴의
완전한 동작 예제이자 **재사용 가능한 템플릿**입니다.

```
                      ┌─────────────────────────────┐
  portal.example.com  │  Portal (YARP reverse proxy)│
   /a  /b  /c  ──────▶│  경로 유지하며 백엔드로 전달 │
                      └───────┬─────────┬─────────┬─┘
                              │ /a      │ /b      │ /c
                         ┌────▼───┐ ┌───▼────┐ ┌──▼─────┐
                         │SampleA │ │SampleB │ │SampleC │  독립 배포되는
                         │  /a    │ │  /b    │ │  /c    │  Blazor Server 앱
                         └────────┘ └────────┘ └────────┘
```

사용자는 `portal.example.com/a`, `/b`, `/c` 만 보고, 각 앱이 실제로 어느 서버/포트에서
도는지는 알 필요도, 알 수도 없습니다. URL은 `/a`, `/b`, `/c` 상태로 그대로 유지됩니다.

> 기술 스택은 **.NET 9 + Blazor Server + YARP**이지만, 핵심 개념(경로 보존 프록시, PathBase,
> base href, WebSocket 포워딩)은 **Nginx / IIS ARR / k8s Ingress 등 모든 리버스 프록시에 그대로
> 적용**됩니다. → [docs/10-alternatives.md](docs/10-alternatives.md)

---

## 30초 만에 실행

```powershell
git clone https://github.com/jaywapp/reverse-proxy-tutorial.git
cd reverse-proxy-tutorial
./run-local.ps1
```

브라우저에서 <http://localhost:5000> 접속 → 카드 클릭 → `/a /b /c` 로 이동.
각 페이지의 **Increment** 버튼이 동작하면 Blazor Server 회로(WebSocket)가 프록시를 통해
정상 연결된 것입니다.

> 요구 사항: [.NET SDK 9.0+](https://dotnet.microsoft.com/download/dotnet/9.0). Windows PowerShell 5.1 호환.

---

## 문서 (교본)

순서대로 읽으면 개념 → 구현 → 배포 → 검증까지 한 번에 익힐 수 있습니다.

| # | 문서 | 내용 |
|---|------|------|
| 01 | [개념과 용어](docs/01-concepts.md) | 리버스 프록시·게이트웨이 라우팅·언제 쓰나·다른 패턴과 비교 |
| 02 | [아키텍처](docs/02-architecture.md) | 요청 흐름, 구성 요소, 왜 이렇게 설계했는가 |
| 03 | [처음부터 직접 만들기](docs/03-build-from-scratch.md) | 빈 폴더에서 따라 만드는 단계별 가이드 |
| 04 | [핵심 기술 4가지](docs/04-key-techniques.md) | PathBase · base href · WebSocket · ForwardedHeaders 심화 |
| 05 | [로컬 실행](docs/05-run-local.md) | run-local.ps1 동작 원리, 포트, 환경 분리 |
| 06 | [IIS 배포](docs/06-deploy-iis.md) | publish → IIS 사이트 구성 → 도메인 연결 |
| 07 | [검증 방법론](docs/07-verification.md) | "정말 동작하는가"를 증명하는 테스트 절차 |
| 08 | [트러블슈팅](docs/08-troubleshooting.md) | 무한 리다이렉트·502.5·WebSocket 끊김·CSS 404 등 |
| 09 | [확장하기](docs/09-extending.md) | 앱 추가, 분산 서버, HTTPS, 인증 |
| 10 | [다른 구현체](docs/10-alternatives.md) | Nginx / IIS ARR / Azure / k8s 로 같은 패턴 구현 |

---

## 저장소 구조

```
reverse-proxy-tutorial/
├── README.md
├── run-local.ps1            # 빌드 + 전체 실행 (로컬)
├── new-backend.ps1          # 새 백엔드 앱을 포털에 추가하는 스캐폴드
├── ReverseProxyTutorial.sln
├── docs/                    # 교본 문서 (위 표)
├── deploy/
│   ├── publish-all.ps1      # 전체 publish
│   └── iis-setup.ps1        # IIS 사이트/앱풀 생성 (관리자)
└── src/
    ├── Portal/              # ★ 템플릿: YARP 게이트웨이 + 랜딩 페이지
    ├── Shared/              # ★ 템플릿: 백엔드 공통 라이브러리
    │   ├── BackendReverseProxyExtensions.cs   # UseBackendReverseProxy()
    │   └── BaseHref.razor                     # <BaseHref /> 컴포넌트
    └── samples/             # 예제 백엔드 (자유롭게 교체/삭제)
        ├── SampleA/  (/a)
        ├── SampleB/  (/b)
        └── SampleC/  (/c)
```

`src/Portal` 와 `src/Shared` 가 **템플릿(재사용 부분)**, `src/samples/*` 는 **예제**입니다.
자신의 앱으로 바꾸려면 samples 를 지우고 `./new-backend.ps1` 로 새 앱을 추가하세요.

---

## 핵심 아이디어 4줄 요약

1. **경로 보존 프록시** — YARP가 `/a` 접두사를 **그대로** 백엔드로 전달(리라이트 X) → URL 유지.
2. **PathBase** — 각 백엔드가 `UsePathBase("/a")` 로 자신이 `/a` 아래 있음을 인지.
3. **동적 base href** — `<BaseHref />` 가 상대 경로(자산·라우팅·SignalR)를 `/a/` 기준으로 해석.
4. **WebSocket 포워딩** — 포털이 Blazor Server의 SignalR 회로(WebSocket)를 그대로 프록시.

자세한 설명: [docs/04-key-techniques.md](docs/04-key-techniques.md)

## License

[MIT](LICENSE)
