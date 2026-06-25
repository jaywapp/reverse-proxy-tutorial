# 07. 검증 방법론

"브라우저에서 열린다"는 동작 증명이 아닙니다. 경로 보존 프록시는 **HTML은 떠도 자산/회로가
새는** 경우가 흔합니다. 이 문서는 각 계층을 실제로 검증하는 절차를 담습니다.
(아래 명령은 Windows PowerShell 5.1 기준. 먼저 `./run-local.ps1` 로 앱을 띄워두세요.)

## 검증 매트릭스

| # | 무엇을 | 어떻게 | 통과 기준 |
|---|--------|--------|-----------|
| 1 | 라우팅 | `/a /b /c` HTML 요청 | 각각 Sample A/B/C 응답 |
| 2 | base href | HTML의 `<base href>` | `/a/`, `/b/`, `/c/` |
| 3 | bare 리다이렉트 | `/a` (슬래시 없음) | 200 + 무한 루프 없음 |
| 4 | 정적 자산 | `blazor.web.js`, CSS | 200 + 실제 바이트 |
| 5 | WebSocket 회로 | raw WS 핸드셰이크 | `State=Open` |

## 1~3. 라우팅 / base href / bare 경로

```powershell
function T($n,$u){
  $r = Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 10
  $title = if ($r.Content -match '<title>([^<]+)</title>') { $Matches[1] } else { '?' }
  $base  = if ($r.Content -match '<base href="([^"]*)"') { $Matches[1] } else { '-' }
  "{0,-10} {1} title='{2}' base={3}" -f $n, $r.StatusCode, $title, $base
}
T "root" "http://localhost:5000/"
T "/a"   "http://localhost:5000/a"     # bare → 리다이렉트되어 200, 루프 없으면 통과
T "/b"   "http://localhost:5000/b"
T "/c"   "http://localhost:5000/c"
```

기대 결과:
```
root       200 title='Portal'   base=-
/a         200 title='Sample A' base=/a/
/b         200 title='Sample B' base=/b/
/c         200 title='Sample C' base=/c/
```

> bare 경로에서 `자동 리디렉션을 너무 많이 시도했습니다` 오류가 나면 무한 루프입니다
> → exact match 로직 확인 ([08. 트러블슈팅](08-troubleshooting.md)).

## 4. 정적 자산이 프록시를 통과하는가

`Invoke-WebRequest` 는 압축/콘텐츠 타입에 따라 길이를 0으로 잘못 측정할 수 있어
`HttpClient` 로 실제 바이트를 잽니다.

```powershell
Add-Type -AssemblyName System.Net.Http
$h = [System.Net.Http.HttpClient]::new()
# 페이지에서 실제(fingerprint된) CSS 경로를 뽑아 프록시로 다시 요청
$page = $h.GetStringAsync("http://localhost:5000/a/").Result
$css  = ([regex]::Match($page,'href="([^"]*bootstrap[^"]*\.css)"')).Groups[1].Value
"blazor.js : $(($h.GetByteArrayAsync('http://localhost:5000/a/_framework/blazor.web.js').Result).Length) bytes"
"css       : $(($h.GetByteArrayAsync("http://localhost:5000/a/$css").Result).Length) bytes"
```

기대: 둘 다 수만~수십만 바이트(0이 아님).

> **주의**: bin 폴더 DLL을 직접 실행하면 정적 자산이 복사되지 않아 CSS가 0바이트로 나올 수
> 있습니다. 이는 프록시 문제가 아니라 실행 방식 문제입니다. `dotnet run`(Development) 또는
> `dotnet publish` 산출물에서는 정상입니다. 즉 **실제 배포 경로에서 검증**하세요.

## 5. WebSocket 회로 (가장 중요)

Blazor Server 인터랙션의 핵심. raw WebSocket 핸드셰이크가 프록시를 통과하는지 확인합니다.

```powershell
function WsTest($label,$uri){
  $ws=[System.Net.WebSockets.ClientWebSocket]::new()
  $cts=[System.Threading.CancellationTokenSource]::new(8000)
  try { $ws.ConnectAsync([Uri]$uri,$cts.Token).Wait(); "$label : State=$($ws.State)"; $ws.Dispose() }
  catch { $e=$_.Exception; while($e.InnerException){$e=$e.InnerException}; "$label : FAIL $($e.Message)" }
}
WsTest "direct backend" "ws://localhost:5001/a/_blazor"   # 백엔드 직접
WsTest "through portal"  "ws://localhost:5000/a/_blazor"   # 프록시 경유
```

기대: 둘 다 `State=Open`. 프록시 경유가 Open이면 WebSocket 업그레이드가 정상 전달된 것입니다.

> `/_blazor/negotiate` 에 POST 했을 때 **405** 가 나는 것은 정상입니다. Blazor는 negotiation을
> 건너뛰고 WebSocket으로 직접 연결합니다. 직접 백엔드와 프록시가 **같은 응답**이면 프록시는
> 결백합니다. 항상 "직접 vs 프록시"를 비교해 문제를 격리하세요.

## 검증의 원칙

1. **계층을 분리해 본다** — HTML / 자산 / WebSocket 을 따로 확인. 한 계층 통과 ≠ 전체 통과.
2. **직접 vs 프록시 비교** — 증상이 프록시 탓인지 백엔드 탓인지 격리.
3. **실제 배포 경로에서** — bin 직접 실행의 인공적 한계에 속지 말 것.
4. **도구의 측정 한계를 의심** — 길이 0, 405 등은 도구 특성일 수 있으니 다른 방법으로 교차 확인.

---

이전 ← [06. IIS 배포](06-deploy-iis.md) · 다음 → [08. 트러블슈팅](08-troubleshooting.md)
