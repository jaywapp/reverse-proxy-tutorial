# 10. 다른 구현체로 같은 패턴 만들기

이 튜토리얼은 YARP로 구현했지만, **게이트웨이 라우팅 패턴 자체는 도구 독립적**입니다.
핵심 4요소([04. 핵심 기술](04-key-techniques.md))는 어떤 프록시에서도 동일하게 챙겨야 합니다:

1. 경로 보존 전달 2. 백엔드의 경로 인지 3. 슬래시로 끝나는 base href 4. WebSocket 전달

아래는 같은 `portal/a → backendA` 구성을 다른 프록시로 구현한 예시입니다.

## Nginx

```nginx
server {
    listen 80;
    server_name portal.example.com;

    location /a/ {
        proxy_pass http://127.0.0.1:5001;        # 경로 보존(/a/ 유지)
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # WebSocket 업그레이드 전달 (Blazor SignalR 필수)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    # /b/, /c/ 동일 반복
}
```

- `proxy_pass` 끝에 경로를 붙이지 않아 `/a/` 가 보존됩니다(trailing slash 규칙 주의).
- 백엔드는 여전히 `UsePathBase("/a")` 가 필요합니다.
- bare `/a` → `/a/` 는 `location = /a { return 301 /a/; }` 로.

## IIS ARR (Application Request Routing)

Windows 환경에서 별도 .NET 코드 없이 IIS만으로 구현:

1. IIS에 **ARR + URL Rewrite** 모듈 설치, 서버 프록시 활성화.
2. 포털 사이트에 URL Rewrite 규칙 추가:
   ```xml
   <rule name="route-a" stopProcessing="true">
     <match url="^a/(.*)" />
     <action type="Rewrite" url="http://localhost:8081/a/{R:1}" />
   </rule>
   ```
3. WebSocket: IIS **WebSocket Protocol 기능** 설치(ARR이 업그레이드 전달).

> 이 튜토리얼은 같은 IIS 위에서 **YARP(.NET 코드)** 로 라우팅합니다. ARR은 코드 없이 IIS 구성만으로
> 같은 일을 하는 대안입니다. 세밀한 변환/로직이 필요하면 YARP, 순수 인프라 구성이면 ARR.

## Kubernetes Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  rules:
  - host: portal.example.com
    http:
      paths:
      - path: /a(/|$)(.*)
        pathType: ImplementationSpecific
        backend: { service: { name: sample-a, port: { number: 80 } } }
      # /b, /c 동일
```

- Ingress 컨트롤러(nginx 등)가 게이트웨이 역할.
- 경로 리라이트 여부에 따라 백엔드 PathBase 또는 base 주입 전략을 맞춰야 합니다.
- WebSocket은 대부분의 Ingress 컨트롤러가 기본 지원(타임아웃만 늘려줄 것).

## Azure Application Gateway / AWS ALB

- **Azure Application Gateway**: path-based routing rule + backend pool. WebSocket 기본 지원.
- **AWS ALB**: listener rule(path pattern `/a/*`) → target group. WebSocket 기본 지원.
- 둘 다 관리형이라 인프라 운영 부담이 적고, 인증/WAF 통합이 강점.

## 선택 가이드

| 상황 | 추천 |
|------|------|
| .NET 생태계, 코드로 세밀 제어 | **YARP** (이 튜토리얼) |
| Windows/IIS, 코드 없이 구성만 | **IIS ARR** |
| Linux, 범용·고성능 | **Nginx** |
| 컨테이너/쿠버네티스 | **Ingress** |
| 클라우드 관리형(운영 최소화) | **Azure App Gateway / AWS ALB** |

어떤 것을 고르든, 백엔드 쪽 4요소(특히 PathBase·base href·WebSocket)는 그대로 적용된다는 점이
이 튜토리얼의 핵심 교훈입니다.

---

이전 ← [09. 확장하기](09-extending.md) · 처음 → [README](../README.md)
