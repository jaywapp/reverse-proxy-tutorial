# 06. IIS 배포

포털 + 백엔드 앱들을 Windows IIS에 올리는 전체 절차입니다.
사용자는 `portal.example.com/a|b|c` 만 보고, 내부 포트(8081~8083)는 노출되지 않습니다.

## 배포 결과 구조

```
[사용자] ─▶ portal.example.com (IIS :80, host header)
                │  Portal 사이트 (Production: cluster → :8081~8083)
                ├─ /a ─▶ IIS 사이트 WebSolution-SampleA  :8081
                ├─ /b ─▶ IIS 사이트 WebSolution-SampleB  :8082
                └─ /c ─▶ IIS 사이트 WebSolution-SampleC  :8083
```

4개가 모두 **독립된 IIS 사이트**입니다(각자 앱풀). 같은 서버에 올리는 것을 기본으로 하며,
다른 서버로 분산하려면 [09. 확장하기](09-extending.md) 참고.

## 0. 서버 사전 준비 (1회)

1. **.NET 9 Hosting Bundle** 설치
   <https://dotnet.microsoft.com/download/dotnet/9.0> → "ASP.NET Core Runtime / Hosting Bundle"
   설치 후 IIS 재시작:
   ```powershell
   net stop was /y; net start w3svc
   ```
2. **IIS WebSocket 기능** 활성화 (Blazor Server 필수):
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebSockets
   ```
   이게 없으면 페이지는 떠도 인터랙션(버튼)이 동작하지 않습니다.

## 1. 게시 (Publish)

```powershell
.\deploy\publish-all.ps1
```

→ `deploy\publish\{Portal,SampleA,SampleB,SampleC}` 생성.
각 폴더에는 `web.config`(ASP.NET Core Module 설정)와 `wwwroot`(정적 자산)가 포함됩니다.

> `dotnet publish` 산출물에는 `wwwroot` 의 모든 정적 자산이 포함됩니다.
> (bin 폴더 직접 실행과 달리 CSS/JS가 정상 제공됩니다.)

## 2. IIS 사이트 생성 (관리자 PowerShell)

```powershell
.\deploy\iis-setup.ps1 -PortalHost portal.example.com
```

이 스크립트가 만드는 것:

| 사이트 | 물리 경로 | 바인딩 | 앱풀(관리 코드 없음) |
|--------|-----------|--------|----------------------|
| WebSolution-SampleA | publish\SampleA | `:8081` | WebSolution-SampleA |
| WebSolution-SampleB | publish\SampleB | `:8082` | WebSolution-SampleB |
| WebSolution-SampleC | publish\SampleC | `:8083` | WebSolution-SampleC |
| WebSolution-Portal  | publish\Portal  | `:80` host `portal.example.com` | WebSolution-Portal |

> 앱풀의 .NET CLR 버전은 "관리 코드 없음(No Managed Code)"으로 설정됩니다.
> ASP.NET Core는 IIS 관리 파이프라인이 아니라 ASP.NET Core Module(ANCM)을 통해 동작하기 때문입니다.

포털은 Production 환경이므로 `appsettings.Production.json` 의 클러스터 주소
(`localhost:8081~8083`)를 사용합니다. ANCM 기본 환경이 Production이라 추가 설정이 필요 없습니다.

## 3. 도메인 연결

- **운영**: DNS A 레코드 `portal.example.com` → 서버 공인 IP
- **로컬 테스트**: `C:\Windows\System32\drivers\etc\hosts` 에
  ```
  127.0.0.1   portal.example.com
  ```

## 4. HTTPS (운영 권장)

포털 사이트에 인증서 바인딩(`:443`)을 추가하고 HTTP→HTTPS 리다이렉트를 둡니다.
TLS는 **포털에서 종단**하고 백엔드와는 HTTP로 통신하는 것이 기본 구성입니다(백엔드는
`UseHttpsRedirection` 을 쓰지 않음). ForwardedHeaders 설정 덕분에 백엔드는 원본이 `https`
였음을 인지합니다. 자세히는 [09. 확장하기](09-extending.md).

## 5. 동작 확인

| URL | 기대 |
|-----|------|
| `http://portal.example.com/`  | 포털 랜딩(카드 3개) |
| `http://portal.example.com/a` | Sample A (주소 `/a` 유지) |
| `/b`, `/c` | Sample B, C |

각 페이지의 **Increment** 버튼이 동작하면 WebSocket까지 정상입니다.

## 포트/도메인 변경

- 백엔드 포트 변경: `deploy\iis-setup.ps1` 의 `$sites` **와** `src\Portal\appsettings.Production.json`
  의 cluster 주소를 **함께** 수정.
- 호스트명 변경: `iis-setup.ps1 -PortalHost <도메인>`.

## 재배포

코드 변경 후:
```powershell
.\deploy\publish-all.ps1          # 다시 게시 (사이트는 그대로 두고 파일만 갱신)
```
파일 잠김으로 게시가 실패하면 해당 앱풀을 잠시 중지 후 다시 시도하세요.

문제 발생 시 → [08. 트러블슈팅](08-troubleshooting.md)

---

이전 ← [05. 로컬 실행](05-run-local.md) · 다음 → [07. 검증 방법론](07-verification.md)
