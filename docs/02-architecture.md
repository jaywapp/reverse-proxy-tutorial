# 02. 아키텍처

## 구성 요소

| 프로젝트 | 종류 | 역할 | dev 포트 | IIS 포트 |
|----------|------|------|----------|----------|
| `src/Portal`  | ASP.NET Core + YARP | `/a /b /c` 라우팅, 랜딩 페이지 | 5000 | 80 (host header) |
| `src/Shared`  | Razor Class Library | 백엔드 공통 코드(PathBase·base href) | — | — |
| `src/samples/SampleA` | Blazor Server | 예제 A (PathBase `/a`) | 5001 | 8081 |
| `src/samples/SampleB` | Blazor Server | 예제 B (PathBase `/b`) | 5002 | 8082 |
| `src/samples/SampleC` | Blazor Server | 예제 C (PathBase `/c`) | 5003 | 8083 |

- **Portal** 과 **Shared** 가 재사용 가능한 "템플릿"입니다.
- **samples/** 는 동작을 보여주는 예제로, 자신의 앱으로 교체 가능합니다.
- 백엔드는 각각 **완전히 독립된 프로세스/사이트**입니다. 포털은 이들을 호출(프록시)만 합니다.

## 요청 흐름 (정상 경로)

`http://portal.example.com/a/counter` 를 예로 든 전체 흐름:

```
1. 브라우저 → portal.example.com/a/counter
2. Portal(YARP): 라우트 "/a/{**catch-all}" 매칭
                 → cluster-a 의 목적지 http://localhost:8081/ 로
                   경로 "/a/counter" 를 "그대로" 전달 (리라이트 없음)
3. SampleA: UsePathBase("/a") 가 "/a" 를 떼어내고 내부 라우팅은 "/counter" 로 처리
4. SampleA: 응답 HTML 생성. <BaseHref /> 가 <base href="/a/"> 출력
5. 브라우저: base href="/a/" 기준으로 상대 경로 해석
            - 정적 자산  → /a/_framework/blazor.web.js
            - SignalR     → /a/_blazor (WebSocket)
6. 그 후속 요청들도 다시 2~3 과정을 거쳐 SampleA 로 전달됨
```

핵심은 **2번에서 경로를 보존**하고 **3번에서 PathBase로 흡수**한다는 점입니다.
덕분에 브라우저 주소창은 `/a/counter` 그대로 유지됩니다(리다이렉트 없음).

## 시퀀스 다이어그램

```
Browser            Portal (YARP)          SampleA (UsePathBase "/a")
  |                    |                          |
  |  GET /a/counter    |                          |
  |------------------->|  GET /a/counter          |
  |                    |------------------------->|
  |                    |                          |  PathBase 제거 → /counter
  |                    |                          |  렌더 + <base href="/a/">
  |                    |<-------------------------|
  |<-------------------|  200 HTML                |
  |                                               |
  |  GET /a/_framework/blazor.web.js (base href 기준)
  |------------------->|------------------------->|  200 JS
  |                                               |
  |  WS  /a/_blazor   (SignalR 회로 업그레이드)    |
  |===================|=========================>|  101 Switching Protocols
  |   (양방향 WebSocket: 버튼 클릭 등 인터랙션)     |
```

## bare 경로 처리 (`/a` → `/a/`)

`<base href>` 는 반드시 슬래시로 끝나야 상대 경로가 올바로 해석됩니다(`/a/` O, `/a` X).
그래서 포털은 슬래시 없는 `/a` 요청을 `/a/` 로 **리다이렉트**합니다.

중요한 함정: 이 리다이렉트가 `/a/` 까지 매칭하면 무한 루프가 됩니다.
그래서 **정확히 일치(exact match)** 할 때만 리다이렉트합니다.
또한 리다이렉트 대상 접두사 목록은 하드코딩하지 않고 **YARP 라우트 설정에서 자동 도출**합니다
(`src/Portal/Program.cs` 의 `PathPrefixes.FromReverseProxyConfig`).

## 환경별 백엔드 주소 분리

포털이 백엔드를 찾는 주소는 환경에 따라 다릅니다.

| 환경 | 설정 파일 | 백엔드 주소 |
|------|-----------|-------------|
| Development (`run-local.ps1`) | `appsettings.json` | `localhost:5001~5003` |
| Production (IIS) | `appsettings.Production.json` | `localhost:8081~8083` |

ASP.NET Core는 `appsettings.{Environment}.json` 을 base 설정 위에 **덮어씌웁니다**.
IIS의 ASP.NET Core Module은 기본 환경이 Production이라 별도 설정 없이 Production 값이 적용됩니다.

## 왜 이렇게 설계했나 (설계 결정)

- **YARP 선택**: Blazor Server는 SignalR(WebSocket)이 필수인데 YARP는 WebSocket 업그레이드를
  기본 지원하고, .NET 생태계와 자연스럽게 통합됩니다. (Nginx/IIS ARR도 가능 → [10](10-alternatives.md))
- **경로 리라이트 대신 보존**: `/a` 를 떼고 백엔드 루트로 보내는 대신 `/a` 를 유지하고 PathBase로
  흡수하면, 앱이 생성하는 모든 링크가 자동으로 `/a/` 접두사를 갖게 되어 새는 링크가 없습니다.
- **공통 코드를 RCL로 추출**: PathBase·ForwardedHeaders·base href 보일러플레이트가 앱마다
  중복되지 않도록 `Shared` 라이브러리로 모았습니다. 새 앱은 두 줄(`AddBackendReverseProxy()`,
  `UseBackendReverseProxy()`)과 `<BaseHref />` 컴포넌트만 쓰면 됩니다.
- **설정 주도 포털**: 라우트/클러스터를 코드가 아닌 `appsettings.json` 에 두어, 앱 추가 시
  포털 코드를 건드리지 않아도 됩니다.

---

이전 ← [01. 개념](01-concepts.md) · 다음 → [03. 처음부터 직접 만들기](03-build-from-scratch.md)
