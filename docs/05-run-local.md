# 05. 로컬 실행

## 한 줄 실행

```powershell
./run-local.ps1
```

이 스크립트가 하는 일:
1. 솔루션을 Release로 빌드
2. 환경변수 `ASPNETCORE_ENVIRONMENT=Development` 설정 (자식 프로세스 상속)
3. 4개 앱을 각각 별도 프로세스로 기동

| 앱 | 주소 |
|----|------|
| Portal | <http://localhost:5000> |
| SampleA | <http://localhost:5001/a> (직접 접근도 가능) |
| SampleB | <http://localhost:5002/b> |
| SampleC | <http://localhost:5003/c> |

브라우저에서 <http://localhost:5000> → 카드 클릭 → `/a /b /c` 이동.

## 동작 확인 포인트

- 주소창이 `localhost:5000/a` **그대로 유지**되는가 (백엔드 포트 5001 노출 안 됨)
- 페이지 상단 배너 색이 앱마다 다른가 (A 파랑 / B 초록 / C 빨강)
- **Increment 버튼**이 눌리는가 → WebSocket 회로 정상
- 페이지의 `BaseUri` 표시가 `http://localhost:5000/a/` 인가

## 포트 구조

```
:5000  Portal      ─┬─ /a ─▶ :5001  SampleA  (PathBase /a)
                    ├─ /b ─▶ :5002  SampleB  (PathBase /b)
                    └─ /c ─▶ :5003  SampleC  (PathBase /c)
```

dev 포트는 각 앱의 `appsettings.json` 의 `Kestrel:Endpoints:Http:Url` 과
포털 `appsettings.json` 의 클러스터 주소에 정의돼 있습니다.

## 왜 Development 환경인가

`run-local.ps1` 은 bin 출력의 DLL을 직접 실행합니다. DLL 직접 실행 시 ASP.NET Core의 기본
환경은 **Production** 이라, 그대로 두면 포털이 `appsettings.Production.json` 의 IIS 포트
(8081~8083)를 보고 백엔드를 못 찾습니다. 그래서 스크립트가 `Development` 로 강제해
base `appsettings.json` 의 dev 포트(5001~5003)를 쓰게 합니다.

## 개별 실행 (디버깅용)

각 앱을 따로 띄우려면 별도 터미널에서:

```powershell
dotnet run --project src\samples\SampleA   # :5001
dotnet run --project src\samples\SampleB   # :5002
dotnet run --project src\samples\SampleC   # :5003
dotnet run --project src\Portal            # :5000
```

`dotnet run` 은 `launchSettings.json` 에 따라 Development로 동작합니다.

## 종료

```powershell
# run-local.ps1 이 출력한 PID 사용
Get-Process -Id <PID들> | Stop-Process

# 또는 이 저장소에서 띄운 프로세스만 정리
Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" |
  Where-Object { $_.CommandLine -like "*reverse-proxy-tutorial\src\*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

## 빌드 건너뛰기

이미 빌드돼 있으면:

```powershell
./run-local.ps1 -NoBuild
```

---

이전 ← [04. 핵심 기술](04-key-techniques.md) · 다음 → [06. IIS 배포](06-deploy-iis.md)
