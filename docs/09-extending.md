# 09. 확장하기

## 새 백엔드 앱 추가 (자동)

스캐폴드 스크립트 한 줄로 끝납니다:

```powershell
./new-backend.ps1 -Name SampleD -Prefix d -DevPort 5004 -IisPort 8084
```

이 스크립트가 자동으로:
1. `src\SampleD` 에 Blazor Server 앱 생성
2. Shared 라이브러리 참조 + 솔루션 등록
3. `appsettings.json` 에 PathBase `/d` 와 dev 포트 설정
4. `Program.cs` 를 공통 헬퍼 사용으로 작성
5. `App.razor` 의 `<base href>` 를 `<BaseHref />` 로 교체
6. 포털 `appsettings.json`/`appsettings.Production.json` 에 route/cluster 등록

실행 후 출력되는 안내대로 `run-local.ps1` 과 `deploy\iis-setup.ps1` 목록에 한 줄씩 추가하면 됩니다.

## 새 백엔드 앱 추가 (수동)

`new-backend.ps1` 없이 직접 한다면 [03. 처음부터 만들기](03-build-from-scratch.md)의 5번을 반복하고,
포털 설정에 다음을 추가합니다:

```json
// appsettings.json (dev) / appsettings.Production.json (IIS, 주소만 다름)
"Routes":   { "route-d":   { "ClusterId": "cluster-d", "Match": { "Path": "/d/{**catch-all}" } } },
"Clusters": { "cluster-d": { "Destinations": { "d1": { "Address": "http://localhost:5004/" } } } }
```

bare 경로 리다이렉트는 라우트에서 자동 도출되므로 포털 **코드는 수정 불필요**합니다.

## 백엔드를 다른 서버로 분산

기본 구성은 모두 한 서버(`localhost`)지만, 클러스터 주소만 바꾸면 분산됩니다.

```json
// appsettings.Production.json
"cluster-a": { "Destinations": { "d1": { "Address": "http://app-server-1:8080/" } } },
"cluster-b": { "Destinations": { "d1": { "Address": "http://app-server-2:8080/" } } }
```

- 백엔드 서버는 포털에서 접근 가능한 네트워크에 있어야 합니다(방화벽/보안그룹).
- PathBase는 백엔드 쪽 설정이므로 그대로 두면 됩니다.

## 부하 분산 (한 백엔드를 여러 인스턴스로)

클러스터에 목적지를 여러 개 두면 YARP가 분산합니다:

```json
"cluster-a": {
  "LoadBalancingPolicy": "RoundRobin",
  "Destinations": {
    "d1": { "Address": "http://app-1:8080/" },
    "d2": { "Address": "http://app-2:8080/" }
  }
}
```

> 주의: Blazor Server는 **상태 유지(stateful) 회로**라 sticky session이 필요합니다.
> YARP의 `SessionAffinity` 를 설정하거나, 백엔드를 ARR Affinity/쿠키로 고정하세요.
> 무상태 API라면 신경 쓸 필요 없습니다.

## HTTPS / TLS

권장 구성: **포털에서 TLS 종단**, 백엔드와는 내부 HTTP.

- 포털 IIS 사이트에 인증서 바인딩(`:443`) 추가, HTTP→HTTPS 리다이렉트.
- 백엔드는 `UseHttpsRedirection` 을 쓰지 않음(이미 그렇게 구성됨).
- ForwardedHeaders 덕분에 백엔드는 원본이 `https` 임을 인지 → 올바른 절대 URL 생성.
- 더 강한 보안이 필요하면 백엔드도 HTTPS로 두고 클러스터 주소를 `https://` 로, 내부 인증서 검증
  정책을 설정합니다.

## 헬스 체크

YARP 능동 헬스 체크로 죽은 백엔드를 자동 제외:

```json
"cluster-a": {
  "HealthCheck": { "Active": { "Enabled": true, "Path": "/a/health", "Interval": "00:00:10" } },
  "Destinations": { "d1": { "Address": "http://localhost:8081/" } }
}
```

백엔드에 `/health` 엔드포인트(`app.MapHealthChecks("/health")`)를 추가하세요.

## 횡단 관심사 (게이트웨이에서 처리)

게이트웨이는 공통 기능을 모으기 좋은 자리입니다:

- **인증/인가**: 포털에서 인증 후 사용자 정보를 헤더로 백엔드에 전달.
- **레이트 리밋**: ASP.NET Core Rate Limiting 미들웨어를 `MapReverseProxy()` 앞에.
- **로깅/추적**: 상관관계 ID(correlation id) 부여 후 전달.
- **응답 변환**: YARP transforms 로 헤더 추가/제거.

## 다른 종류의 백엔드

이 패턴은 Blazor Server 전용이 아닙니다. 정적 사이트, MVC, 외부 API, 다른 언어로 만든 서버도
같은 방식으로 붙일 수 있습니다. 단, **그 백엔드가 경로 접두사(`/a`)를 인지**하도록 해당 기술의
방식(PathBase 상당 기능, base tag, 리라이트)을 적용해야 합니다.

---

이전 ← [08. 트러블슈팅](08-troubleshooting.md) · 다음 → [10. 다른 구현체](10-alternatives.md)
