# 03. 처음부터 직접 만들기

이 저장소를 클론하지 않고 **빈 폴더에서** 똑같은 구조를 손으로 만들어 보는 가이드입니다.
원리를 손에 익히는 것이 목적입니다. (바로 쓰고 싶다면 [05. 로컬 실행](05-run-local.md)으로.)

> 전제: [.NET SDK 9.0+](https://dotnet.microsoft.com/download/dotnet/9.0) 설치.
> 확인: `dotnet --version` → `9.x`

## 0. 솔루션 골격

```powershell
mkdir reverse-proxy-tutorial; cd reverse-proxy-tutorial
dotnet new sln -n ReverseProxyTutorial
mkdir src, src\samples, deploy, docs
```

## 1. 백엔드 앱 3개 (Blazor Server)

```powershell
dotnet new blazor -n SampleA -o src\samples\SampleA --interactivity Server
dotnet new blazor -n SampleB -o src\samples\SampleB --interactivity Server
dotnet new blazor -n SampleC -o src\samples\SampleC --interactivity Server
```

`--interactivity Server` 가 핵심입니다. 이 모드가 SignalR(WebSocket) 회로를 사용하며,
바로 그 점이 리버스 프록시에서 까다로운 부분입니다.

## 2. 포털 앱 (YARP)

```powershell
dotnet new web -n Portal -o src\Portal
dotnet add src\Portal\Portal.csproj package Yarp.ReverseProxy
```

`web` 템플릿은 최소 ASP.NET Core 앱입니다. 여기에 YARP를 얹어 라우팅만 담당하게 합니다.

## 3. 공통 라이브러리 (선택이지만 권장)

백엔드 보일러플레이트를 한 곳에 모으는 Razor Class Library입니다.

```powershell
dotnet new razorclasslib -n ReverseProxy.Backend.Shared -o src\Shared
# 템플릿 기본 파일 정리
del src\Shared\Class1.cs, src\Shared\Component1.razor, src\Shared\Component1.razor.css, src\Shared\ExampleJsInterop.cs
rmdir /s /q src\Shared\wwwroot
```

`src/Shared/ReverseProxy.Backend.Shared.csproj` 의 패키지 참조를 프레임워크 참조로 교체:

```xml
<ItemGroup>
  <FrameworkReference Include="Microsoft.AspNetCore.App" />
</ItemGroup>
```

확장 메서드 `src/Shared/BackendReverseProxyExtensions.cs` 와 컴포넌트 `src/Shared/BaseHref.razor`
를 추가합니다(전체 내용은 이 저장소의 동일 파일 참고). 핵심만:

```csharp
public static WebApplication UseBackendReverseProxy(this WebApplication app)
{
    app.UseForwardedHeaders();
    var pathBase = app.Configuration["PathBase"];
    if (!string.IsNullOrWhiteSpace(pathBase)) app.UsePathBase(pathBase);
    return app;
}
```

```razor
@* BaseHref.razor *@
@inject IConfiguration Configuration
<base href="@Configuration.GetBaseHref()" />
```

## 4. 솔루션에 등록 + 참조 연결

```powershell
dotnet sln add src\Portal\Portal.csproj src\Shared\ReverseProxy.Backend.Shared.csproj `
               src\samples\SampleA\SampleA.csproj src\samples\SampleB\SampleB.csproj src\samples\SampleC\SampleC.csproj
foreach ($s in "SampleA","SampleB","SampleC") {
  dotnet add "src\samples\$s\$s.csproj" reference src\Shared\ReverseProxy.Backend.Shared.csproj
}
```

## 5. 각 백엔드 설정 (예: SampleA)

**`src/samples/SampleA/appsettings.json`** — PathBase와 dev 포트:

```json
{
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } },
  "AllowedHosts": "*",
  "PathBase": "/a",
  "Kestrel": { "Endpoints": { "Http": { "Url": "http://localhost:5001" } } }
}
```

**`src/samples/SampleA/Program.cs`** — 공통 헬퍼 사용:

```csharp
using ReverseProxy.Backend.Shared;
using SampleA.Components;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddBackendReverseProxy();          // ← forwarded headers

var app = builder.Build();
app.UseBackendReverseProxy();                        // ← forwarded headers + PathBase

if (!app.Environment.IsDevelopment())
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
app.UseAntiforgery();
app.MapStaticAssets();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.Run();
```

> 템플릿 기본 Program.cs 에 있던 `app.UseHttpsRedirection()` 은 **제거**합니다.
> 백엔드는 프록시 뒤에서 HTTP로 동작하므로 HTTPS 리다이렉트는 루프/혼선을 유발합니다.
> TLS는 포털(또는 그 앞단)에서 종단합니다.

**`src/samples/SampleA/Components/App.razor`** — `<base href="/" />` 를 교체:

```razor
<BaseHref />
```

**`src/samples/SampleA/Components/_Imports.razor`** 끝에 추가:

```razor
@using ReverseProxy.Backend.Shared
```

SampleB는 `/b`·5002, SampleC는 `/c`·5003 으로 동일하게 반복합니다.

## 6. 포털 설정

**`src/Portal/appsettings.json`** — 라우트/클러스터(dev 포트):

```json
{
  "Kestrel": { "Endpoints": { "Http": { "Url": "http://localhost:5000" } } },
  "ReverseProxy": {
    "Routes": {
      "route-a": { "ClusterId": "cluster-a", "Match": { "Path": "/a/{**catch-all}" } },
      "route-b": { "ClusterId": "cluster-b", "Match": { "Path": "/b/{**catch-all}" } },
      "route-c": { "ClusterId": "cluster-c", "Match": { "Path": "/c/{**catch-all}" } }
    },
    "Clusters": {
      "cluster-a": { "Destinations": { "d1": { "Address": "http://localhost:5001/" } } },
      "cluster-b": { "Destinations": { "d1": { "Address": "http://localhost:5002/" } } },
      "cluster-c": { "Destinations": { "d1": { "Address": "http://localhost:5003/" } } }
    }
  }
}
```

**`src/Portal/appsettings.Production.json`** — IIS용 백엔드 주소만 덮어쓰기:

```json
{
  "ReverseProxy": { "Clusters": {
    "cluster-a": { "Destinations": { "d1": { "Address": "http://localhost:8081/" } } },
    "cluster-b": { "Destinations": { "d1": { "Address": "http://localhost:8082/" } } },
    "cluster-c": { "Destinations": { "d1": { "Address": "http://localhost:8083/" } } }
  } }
}
```

**`src/Portal/Program.cs`**:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();
app.UseWebSockets();              // ← Blazor SignalR 회로에 필수
app.UseDefaultFiles();
app.UseStaticFiles();             // ← 랜딩 페이지(wwwroot/index.html)

// bare "/a" → "/a/" 리다이렉트 (정확히 일치할 때만; 접두사는 라우트에서 도출)
var prefixes = PathPrefixes.FromReverseProxyConfig(builder.Configuration);
app.Use(async (ctx, next) => {
    var path = ctx.Request.Path.Value ?? "";
    if (prefixes.Contains(path)) { ctx.Response.Redirect($"{ctx.Request.PathBase}{path}/"); return; }
    await next();
});

app.MapReverseProxy();
app.Run();
```

`PathPrefixes` 헬퍼 전체 코드는 이 저장소의 `src/Portal/Program.cs` 를 참고하세요.
포털 `wwwroot/index.html` 에 간단한 랜딩 페이지를 두면 루트(`/`)에서 카드 메뉴를 보여줄 수 있습니다.

## 7. 빌드 & 실행

```powershell
dotnet build -c Release
# 4개 앱을 각각 실행 (별도 터미널 또는 run-local.ps1)
```

자세한 실행은 [05. 로컬 실행](05-run-local.md), 동작 원리 심화는 [04. 핵심 기술](04-key-techniques.md).

---

이전 ← [02. 아키텍처](02-architecture.md) · 다음 → [04. 핵심 기술](04-key-techniques.md)
