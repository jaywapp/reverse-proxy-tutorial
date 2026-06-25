# 04. 핵심 기술 4가지

경로 기반 리버스 프록시에서 "그냥 프록시만 하면 되는 거 아냐?" 싶지만, 실제로는 네 가지를
정확히 맞춰야 동작합니다. 하나라도 빠지면 **링크 깨짐 / 무한 리다이렉트 / 인터랙션 불능** 으로 이어집니다.

---

## 1. 경로 보존 프록시 (Path-preserving forwarding)

### 문제
백엔드를 어떻게 호출할 것인가? 두 가지 선택:

| 방식 | 백엔드가 받는 경로 | 결과 |
|------|-------------------|------|
| **리라이트(strip)** | `/a/counter` → `/counter` | 백엔드는 루트에서 동작. 하지만 백엔드가 만드는 링크는 `/counter`, `/css/...` 처럼 **접두사가 빠져** 브라우저에서 `/css/...` (포털 루트)로 새어나감. |
| **보존(preserve)** ✅ | `/a/counter` → `/a/counter` | 백엔드가 `/a` 를 인지(PathBase)하고 모든 링크에 `/a` 를 붙임. 새는 링크 없음. |

### 구현
YARP 라우트의 매치 경로를 catch-all로 두고, **transform을 쓰지 않으면** 경로가 그대로 전달됩니다.

```json
"route-a": { "ClusterId": "cluster-a", "Match": { "Path": "/a/{**catch-all}" } },
"cluster-a": { "Destinations": { "d1": { "Address": "http://localhost:5001/" } } }
```

`/a/counter` 요청 → 목적지 `http://localhost:5001/` + 원본 경로 `/a/counter` = `http://localhost:5001/a/counter`.
**접두사 `/a` 가 그대로 살아서** 백엔드에 도착합니다.

> 만약 리라이트 방식을 쓰고 싶다면 YARP의 `PathRemovePrefix` transform이 있지만, 그러면
> 백엔드에서 base href를 별도 주입해야 하는 등 오히려 복잡해집니다. 보존이 정석입니다.

---

## 2. PathBase — 백엔드가 자기 경로를 인지

### 문제
경로를 보존해서 `/a/counter` 가 백엔드에 도착했는데, 백엔드의 라우팅은 `/counter` 를 기대합니다.
`/a` 를 누가 떼어줄 것인가?

### 구현
`UsePathBase("/a")` 가 요청 경로 앞의 `/a` 를 떼어 `HttpContext.Request.PathBase` 에 보관하고,
이후 미들웨어는 `/counter` 만 보게 합니다. 동시에 앱이 생성하는 링크에는 `/a` 가 자동으로 붙습니다.

```csharp
// Shared/BackendReverseProxyExtensions.cs
public static WebApplication UseBackendReverseProxy(this WebApplication app)
{
    app.UseForwardedHeaders();
    var pathBase = app.Configuration["PathBase"];      // "/a"
    if (!string.IsNullOrWhiteSpace(pathBase))
        app.UsePathBase(pathBase);                     // 파이프라인 맨 앞
    return app;
}
```

**순서가 중요합니다.** `UsePathBase` 는 라우팅·정적파일보다 **먼저** 와야 합니다. 그래서
`Build()` 직후 가장 먼저 호출합니다.

PathBase 값은 코드가 아니라 설정(`appsettings.json` 의 `"PathBase": "/a"`)에서 읽습니다.
덕분에 **같은 코드**가 환경/앱에 따라 다른 경로로 동작할 수 있습니다.

---

## 3. 동적 `<base href>` — 브라우저의 상대 경로 기준

### 문제
HTML의 상대 경로(`_framework/blazor.web.js`, `css/app.css`)는 `<base href>` 를 기준으로 해석됩니다.
Blazor 템플릿 기본값은 `<base href="/" />` 입니다. 그러면 브라우저는 자산을 `/`(포털 루트)에서
찾아 **404** 가 납니다. `/a/` 기준이어야 `/a/_framework/...` 로 올바르게 요청합니다.

또한 `<base href>` 는 **반드시 슬래시로 끝나야** 합니다.
`/a` (X) → 마지막 세그먼트가 잘려 `_framework` 가 루트로 붙음. `/a/` (O).

### 구현
PathBase 설정값으로부터 `/a/` 를 만들어 `<base href>` 에 출력하는 컴포넌트:

```razor
@* Shared/BaseHref.razor *@
@inject IConfiguration Configuration
<base href="@Configuration.GetBaseHref()" />
```

```csharp
// "/a" -> "/a/", 없으면 "/"
public static string GetBaseHref(this IConfiguration configuration)
{
    var pathBase = configuration["PathBase"];
    return string.IsNullOrWhiteSpace(pathBase) ? "/" : "/" + pathBase.Trim('/') + "/";
}
```

`App.razor` 에서 `<base href="/" />` 대신 `<BaseHref />` 를 씁니다.
이것으로 정적 자산, Blazor 라우팅, SignalR 엔드포인트 URL이 모두 `/a/` 기준으로 맞춰집니다.

### bare 경로 리다이렉트
사용자가 `/a` (슬래시 없이)로 들어오면 base href가 어긋나므로, 포털이 `/a/` 로 리다이렉트합니다.
단, `/a/` 까지 리다이렉트하면 **무한 루프** → 그래서 **정확히 일치할 때만** 리다이렉트:

```csharp
if (prefixes.Contains(path)) {                  // path == "/a" 만, "/a/" 는 제외
    ctx.Response.Redirect($"{ctx.Request.PathBase}{path}/");
    return;
}
```

`prefixes` 집합은 YARP 라우트 설정에서 자동 도출하므로 하드코딩이 없습니다.

---

## 4. WebSocket 포워딩 — Blazor Server의 생명줄

### 문제
Blazor Server는 첫 HTML 이후 모든 인터랙션(버튼 클릭, UI 갱신)을 **SignalR 회로**로 처리합니다.
이 회로는 **WebSocket** 으로 연결됩니다(`/_blazor`). 프록시가 WebSocket 업그레이드(`101 Switching
Protocols`)를 전달하지 못하면, 페이지는 떠도 **버튼이 안 먹습니다**.

### 구현 (두 곳)

포털: WebSocket 미들웨어 활성화. YARP는 업그레이드를 자동 전달합니다.

```csharp
app.UseWebSockets();   // 이 한 줄이 없으면 회로가 붙지 않음
app.MapReverseProxy();
```

백엔드: PathBase 덕분에 회로 엔드포인트가 `/a/_blazor` 로 노출되고, base href가 `/a/` 라
클라이언트가 정확히 그 주소로 WebSocket을 엽니다.

IIS 배포 시에는 추가로 **IIS의 "WebSocket Protocol" 기능**이 설치돼 있어야 합니다
([06. IIS 배포](06-deploy-iis.md) 참고).

### 검증
실제로 통과하는지는 raw WebSocket 핸드셰이크로 확인할 수 있습니다(자세히는 [07. 검증](07-verification.md)):

```powershell
$ws=[System.Net.WebSockets.ClientWebSocket]::new()
$ws.ConnectAsync([Uri]"ws://localhost:5000/a/_blazor",
                 [System.Threading.CancellationTokenSource]::new(8000).Token).Wait()
$ws.State    # Open 이면 프록시가 WebSocket 업그레이드를 전달한 것
```

---

## 추가: ForwardedHeaders

프록시 뒤에 있으면 백엔드가 보는 요청의 scheme/host/client IP가 **프록시의 것**이 됩니다.
원래 값(`https`, `portal.example.com`, 실제 클라이언트 IP)을 알려면 프록시가 붙이는
`X-Forwarded-*` 헤더를 신뢰하도록 설정해야 합니다.

```csharp
services.Configure<ForwardedHeadersOptions>(o => {
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor
                       | ForwardedHeaders.XForwardedProto
                       | ForwardedHeaders.XForwardedHost;
    o.KnownNetworks.Clear();   // 프록시 주소가 가변(컨테이너/IIS) → 운영선 강화 권장
    o.KnownProxies.Clear();
});
...
app.UseForwardedHeaders();     // UsePathBase 와 함께 파이프라인 앞쪽
```

리다이렉트 URL 생성, 절대 링크, 로깅의 정확도를 위해 필요합니다. 보안상 운영 환경에서는
`KnownProxies`/`KnownNetworks` 를 실제 프록시 주소로 좁히는 것을 권장합니다.

---

## 4가지 체크리스트

- [ ] YARP 라우트가 catch-all 이고 경로를 **보존**하는가 (transform 없음)
- [ ] 백엔드가 `UsePathBase(설정값)` 를 **파이프라인 맨 앞**에서 호출하는가
- [ ] `<base href>` 가 `/a/` 처럼 **슬래시로 끝나는** 동적 값인가
- [ ] 포털 `UseWebSockets()` + (IIS면) WebSocket 기능이 켜져 있는가

---

이전 ← [03. 처음부터 만들기](03-build-from-scratch.md) · 다음 → [05. 로컬 실행](05-run-local.md)
