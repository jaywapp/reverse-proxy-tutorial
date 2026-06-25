# 08. 트러블슈팅

증상 → 원인 → 해결 순으로 정리했습니다. 대부분 [04. 핵심 기술](04-key-techniques.md)의
네 가지 중 하나가 어긋난 경우입니다.

## 무한 리다이렉트 (`/a` 접속 시 "리디렉션을 너무 많이 시도")

- **원인**: bare 경로 리다이렉트가 `/a/` 까지 매칭해 `/a/ → /a/ → ...` 루프.
- **해결**: **정확히 일치(exact match)** 일 때만 리다이렉트. 라우트 패턴(`/a/{**catch-all}`)이
  처리하는 `/a/` 는 건드리지 않아야 합니다.
  ```csharp
  if (prefixes.Contains(path)) { ... }   // path=="/a" 만, "/a/" 제외 (O)
  app.MapGet("/a", ...)                   // "/a/" 도 매칭됨 → 루프 (X)
  ```

## 페이지는 뜨는데 CSS/JS가 깨짐 (404)

- **원인 1**: `<base href>` 가 `/` 또는 슬래시 없는 `/a` → 자산이 루트로 새거나 경로 잘림.
- **해결**: `<BaseHref />` 사용. 결과가 `/a/` (슬래시로 끝남)인지 확인.
- **원인 2**: bin 폴더 DLL 직접 실행 → 정적 자산 미복사.
- **해결**: `dotnet run` 또는 `dotnet publish` 산출물로 실행. ([07. 검증](07-verification.md))

## 버튼/인터랙션이 안 먹음 (페이지는 정상)

- **원인**: WebSocket(SignalR 회로) 이 프록시를 통과하지 못함.
- **해결**:
  - 포털에 `app.UseWebSockets();` 가 `MapReverseProxy()` 앞에 있는가.
  - (IIS) **WebSocket Protocol 기능** 설치: `Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebSockets`
  - [07. 검증](07-verification.md)의 WS 테스트로 `State=Open` 확인.

## 502.5 ANCM Out-Of-Process / In-Process Startup Failure (IIS)

- **원인**: .NET 9 Hosting Bundle 미설치 또는 런타임 버전 불일치.
- **해결**: [Hosting Bundle](https://dotnet.microsoft.com/download/dotnet/9.0) 설치 후
  `net stop was /y; net start w3svc`. 이벤트 뷰어 → Windows 로그 → 응용 프로그램에서 상세 확인.

## 포털은 뜨는데 `/a` 에서 502/504 (백엔드 연결 실패)

- **원인**: 클러스터 주소가 실제 백엔드와 불일치, 또는 백엔드 사이트 중지.
- **해결**: 환경에 맞는 설정을 확인.
  - Development → `src/Portal/appsettings.json` (포트 5001~5003)
  - Production(IIS) → `src/Portal/appsettings.Production.json` (포트 8081~8083)
  - 백엔드를 직접 열어 살아있는지 확인(`http://localhost:8081/a`).

## 무한 HTTPS 리다이렉트 / "too many redirects" (백엔드)

- **원인**: 백엔드에 `app.UseHttpsRedirection()` 이 남아 있음. 프록시 뒤 HTTP 백엔드가
  HTTPS로 리다이렉트하려 시도.
- **해결**: 백엔드에서 `UseHttpsRedirection` 제거. TLS는 포털에서 종단.

## 로그인/리다이렉트 URL이 `http://` 또는 잘못된 호스트로 생성됨

- **원인**: ForwardedHeaders 미적용 → 백엔드가 원본 scheme/host를 모름.
- **해결**: `AddBackendReverseProxy()` + `UseBackendReverseProxy()`(내부에서 `UseForwardedHeaders`)
  적용. 운영에서는 `KnownProxies`/`KnownNetworks` 를 실제 프록시로 좁히기.

## 새 앱을 추가했는데 라우팅 안 됨

- **체크리스트**:
  - 포털 `appsettings.json` **과** `appsettings.Production.json` 양쪽에 route/cluster 추가했는가.
  - 백엔드 `appsettings.json` 의 `PathBase` 와 라우트 접두사가 일치하는가.
  - `run-local.ps1` / `iis-setup.ps1` 목록에 새 앱을 추가했는가.
  - `./new-backend.ps1` 을 쓰면 위를 자동 처리합니다. ([09. 확장하기](09-extending.md))

## Kestrel 포트 충돌 (`Failed to bind to address`)

- **원인**: 같은 포트를 쓰는 다른 프로세스가 이미 실행 중.
- **해결**: 이전 인스턴스 종료([05. 로컬 실행](05-run-local.md)의 종료 명령) 또는 포트 변경.

---

이전 ← [07. 검증](07-verification.md) · 다음 → [09. 확장하기](09-extending.md)
