# Hermes VPS / Docker 환경에서 8.2 ~ 8.5 진행하기

강의 가이드(8.2 Supabase 시세 DB → 8.3 백테스트 → 8.4 아침 주문 루프 → 8.5 투자위원회)는
노트북에서 터미널을 연 상황을 기준으로 쓰여 있습니다. VPS의 Docker 컨테이너에서 돌리면
**명령은 같지만 몇 군데가 다르게 동작**합니다. 이 문서는 그 차이만 모아 두고, 각 유닛의 진행 순서를
Docker 기준으로 다시 정리합니다. 프롬프트 원문은 `magma-finance-lab/PROMPTS.md`를 그대로 씁니다.

> 모든 실습은 키움 **모의투자(demo)** 계좌만 사용합니다. 투자 권유가 아닙니다.

---

## 0. 시작 전에: Docker라서 다른 네 가지

### 0-1. 셸은 항상 "기본 사용자 + 로그인 셸"로 들어간다

접속 방법과 도우미(`hsh`, `hx`, `hp`)는 [운영 가이드](./hermes-vps-operations.md) 2장을 따릅니다.

```bash
source scripts/hermes-env.sh     # VPS 호스트에서, HC 자동 설정
hsh                              # = docker exec -it -u hermes "$HC" bash -l
cd ~/.hermes/workspace/magma-finance-lab
```

- **`-u hermes`로 들어갑니다**(`hsh`가 그렇게 함). 게이트웨이·카드·크론이 `hermes` 사용자로 돌기 때문에, root로 만든 파일은 그쪽에서 못 읽거나 못 쓸 수 있습니다.
- `bash -l`을 빼면 `~/.local/bin`이 PATH에 없어 `kiwoomcli`/`hermes` not found가 납니다
  (8.5 가이드의 `export PATH="$HOME/.local/bin:$PATH"` 경고와 같은 원인).
- `HERMES_HOME`이 `~/.hermes`가 아니면(운영 가이드 3장에서 확인) 가이드의 `~/.hermes/workspace/...` 경로를
  실제 경로로 바꿔 씁니다. 8.5 council 레지스트리도 `$HERMES_HOME/.council`에 생깁니다.
- 프로필은 `hermes profile use`로 전환하지 말고 `hermes -p <프로필>`(= `hp <프로필>`)로 부릅니다.

### 0-2. 컨테이너를 재생성해도 남아야 하는 것 (볼륨)

| 경로 | 무엇이 들어 있나 | 볼륨 밖이면 |
| --- | --- | --- |
| `~/.hermes` (또는 `$HERMES_HOME`) | 프로필·SOUL·스킬·칸반·크론·workspace·council 기록 | 8.2 이후 전부 유실 |
| `~/.local` | `uv tool install kwcli`, `hermes` 실행 파일, uv 캐시 | `kiwoomcli` 사라짐 |
| `~/.local/share/python_keyring` | 8.1의 App Key·Secret (파일 백엔드) | 8.1 재설정 필요 |
| `~/.hermes/workspace/vibe-finance-kit/.venv` | Ada MCP가 **절대경로로** 등록된 실행 파일 | Ada MCP 연결 끊김 |

`docker compose up -d`로 이미지만 갱신해도 컨테이너는 재생성됩니다. `scripts/docker-preflight.sh`의
1번 항목이 이 네 경로가 볼륨 안에 있는지 확인합니다.

### 0-3. 키움 자격 증명은 컨테이너 안, 볼륨 위에

이 VPS 컨테이너에는 OS Keyring(DBus·GNOME Keyring)이 없어 강의 방식의 `kiwoomcli setup`이 그대로는 멈춥니다.
**[8.1 보완 문서](./8.1-kiwoomcli-in-container.md)** 대로 `keyrings.alt` 파일 백엔드를 `/opt/data`에 설정하면,
설정 파일이 HOME(`/opt/data`) 기준이라 터미널·게이트웨이·카드·크론 모두 같은 저장소를 보고,
컨테이너가 재시작되어도 unlock할 필요가 없습니다(모의계좌 전용).

8.2 카드를 만들기 전 확인:
1. 컨테이너 셸에서 `kiwoomcli auth status --profile 모의계좌` 통과
2. **메신저에서 Sam에게** 강의 8.1의 읽기 전용 preflight 프롬프트 → 같은 값
   (카드·크론·메신저는 게이트웨이 프로세스에서 돌기 때문)

강의 저장소 규칙대로 `.env`에 키를 넣어 우회하지 않습니다.

### 0-4. 시간대와 대시보드 접근

- Docker 기본 시간대는 UTC입니다. **이 VPS는 Hermes `timezone: Asia/Seoul` 설정으로 해결했습니다(운영 가이드 3-2).** 8.2의 **평일 18:30** 수집 크론, 8.4의 **평일 08:40** 판단 크론이
  9시간 어긋나 돌 수 있습니다. 컨테이너에 `TZ=Asia/Seoul`(+ `tzdata`)을 주고 게이트웨이를 재기동하거나,
  크론 등록 후 "다음 실행 시각"의 시간대 표기를 반드시 확인합니다.
  (백테스트·수집 스크립트는 내부적으로 `Asia/Seoul`을 쓰므로 영향은 크론 시각뿐입니다.)
- 칸반 대시보드 포트는 VPS 공인 IP에 열지 말고 SSH 터널로 봅니다.
  `ssh -L <포트>:localhost:<포트> <vps>` — 컨테이너 포트가 호스트 `127.0.0.1`에만 publish되어 있어야 합니다.

### 0-5. 한 번에 점검

```bash
# VPS 호스트, 이 저장소 폴더에서
HERMES_CONTAINER=<컨테이너> HERMES_USER=<사용자> ./scripts/docker-preflight.sh
```

읽기 전용입니다. `[FAIL]`은 진행 전에 고치고, `[WARN]`은 해당 유닛 전에 정리합니다.

---

## 8.2 Supabase 시세 DB (Docker 순서)

모든 명령은 0-1의 방식으로 컨테이너 안에서 실행합니다.

1. **스타터 폴더 확인** — 8.1에서 clone했으므로 이동만 합니다.
   `cd ~/.hermes/workspace/magma-finance-lab && git pull --ff-only`
2. **분석 도구 설치**
   ```bash
   cd ~/.hermes/workspace
   git clone https://github.com/dandacompany/vibe-finance-kit.git
   cd vibe-finance-kit
   uv run python scripts/setup_hermes.py      # "Enable all 4 tools?" → Y
   ```
   - 대화형 질문이 있으므로 `docker exec -it` 셸에서 실행합니다(`-it` 없이 스크립트로 돌리면 멈춤).
   - `.venv`가 볼륨 안에 있는지 확인(0-2). 설치 영수증은
     `magma-finance-lab/artifacts/setup/setup-receipt-vibe-finance-kit.json`에 생깁니다.
     `~/.hermes/workspace/magma-finance-lab`이 없는 경로 구성이면 영수증이 vibe-finance-kit 쪽에
     떨어지므로 `--receipt-dir`로 지정합니다.
3. **권한 경계 확인** — Oliver(주문 도구 없음), Ada(`finance_kit_doctor`, 고정 샘플 검증). 새 세션에서.
4. **키움 연결 증거** — Sam: `command -v kiwoomcli` / `auth status` / `doctor` → `artifacts/setup/broker-capabilities.json`,
   `order_enabled: false`.
5. **재료 점검** (Ada) → **마이그레이션 계획만 먼저** → 범위 확인(스키마 1·테이블 4·인덱스 1) → core SQL만 승인.
   - Supabase MCP OAuth가 7.1에서 호스트 브라우저 기준으로 붙어 있었다면, 컨테이너 안 Ada에서도
     연결되는지 먼저 "프로젝트 이름과 ref만 확인" 프롬프트로 봅니다.
6. **칸반 카드** — 보드 생성(workdir 고정) → Sam 수집 / Oliver 조사 → Ada 품질 검증(dependency).
   - 카드 전에 **0-3 키움 자격 증명 확인을 끝내 둡니다.** Sam 수집 카드가 인증 오류로만 끝나면 이 문제입니다.
   - 대시보드에서 카드를 만들 때 workspace는 `dir`.
7. **적재 승인 댓글** → ready → dispatch → 콘솔에서 `finance.daily_prices` 확인.
8. **분석 스냅샷 카드** → `/clear` 후 새 세션 독립 검증
   (`python3 scripts/validate_artifact.py artifacts/analysis/etf-analysis-snapshot-069500.json`).
9. **평일 18:30 수집 크론** — 등록 후 다음 실행 시각의 시간대가 KST인지 확인(0-4).

## 8.3 백테스트 (Docker 순서)

Docker 고유 이슈는 거의 없습니다. 파일을 **사람이 직접 고치는** 단계(10단계 `backtest/rules.md` 근거 칸)만 방법을 정합니다:
컨테이너 안 `nano`/`vim`, 또는 호스트에서 볼륨 경로를 직접 편집, 또는 VS Code Remote-SSH + Dev Containers.

1. `git pull --ff-only` → `backtest/rules.md`, `contracts/backtest-report.schema.json` 확인
2. Ada: 준비물 대조("공통 기간의 일봉이 빠짐없이 있는가" 기준)
3. rules.md 다섯 문장 검사(사람)
4. Ada: 보정(~2020-12-30, 시작일은 공통 기간 첫 거래일) / 평가(2021~) 실행 — **손 검산·감사는 하지 말라는 두 줄 유지**
5. 사이클 1개 손 검산(시가 열로 대조) → 3개 국면 구간 추가 실행
6. 감사 → 경고 확인 → hand-check 기록 후 재감사
7. rules.md 근거 칸을 사람이 기록

## 8.4 아침 주문 루프 (Docker 순서)

1. `git pull --ff-only` — 8.3에서 rules.md를 직접 고쳤다면 **중단되는 게 정상**. 가이드 1단계의 병합 위임 프롬프트를 Sam에게.
2. **pull이 끝난 뒤** `guardrails/limits.md` 값을 검토하고 `status: confirmed`를 사람이 직접 저장
   (순서가 바뀌면 pull이 또 충돌).
3. Sam preflight → Ada·Noah 직무 분리 확인 → `PROMPTS.md` 8.4의 SOUL 규칙 블록 설치 후 `SOUL.md`를 눈으로 확인
   (`~/.hermes/profiles/sam/SOUL.md` 등, `$HERMES_HOME` 기준).
4. 슬랙에서 **사람이 직접** `@Sam 판단 루프를 지금 한 번 돌려줘` → 승인 요청 여덟 항목 확인
5. `@Sam 보류…` → 주문 안 나감 확인 → `@Sam 승인` (만료 약 10분)
6. 대사 → 기록 갱신 → Noah 하루 보고
7. `@Sam 판단 루프를 평일 아침 8시 40분에 예약해줘` → **다음 실행 시각의 시간대 확인**

Docker 주의:
- 슬랙 이벤트를 받는 것도, 크론이 도는 것도 게이트웨이입니다. 컨테이너 재시작 뒤에는
  [운영 가이드](./hermes-vps-operations.md) 5장 "재시작 뒤 체크리스트"로 게이트웨이·`kiwoomcli auth status`·크론 시간대를 확인합니다.
  인증이 실패해도 루프 규칙상 "재시도하지 않고 보고하고 멈춤"이라 주문이 잘못 나가지는 않습니다.

## 8.5 투자위원회 (Docker 순서)

```bash
hermes -p sophie plugins install dandacompany/hermes-council --enable
hermes -p sophie plugins list        # council ≥ 0.13.0, enabled
hermes -p sophie council doctor      # 플러그인·게이트웨이·칸반·기록 폴더 4항목
```

- `doctor`의 **gateway running**은 `hermes gateway status`를 파싱합니다. 게이트웨이가 다른 컨테이너/
  다른 사용자로 떠 있으면 실패로 보입니다 — 같은 컨테이너·같은 사용자에서 실행.
- **registry writable**은 `$HERMES_HOME/.council`(없으면 `~/.hermes/.council`)입니다. 볼륨 안이어야 기록이 남습니다.
- 회의 참여 프로필(sophie·ada·oliver·noah)의 `approvals.mode`가 `manual`이면 백그라운드 카드가
  승인 대기로 멈춥니다. 막히면 해당 프로필 승인 처리 후 `council resume`.

진행:
1. `git pull --ff-only` → `ls briefs/` → `cp briefs/council-brief-example.md briefs/council-brief.md` (**mv 아님**)
2. 일곱 칸을 **자기 8.3·8.4 결과로** 교체. 없는 값은 비었다고 적고, 대괄호 자리표시자가 남지 않게. 맨 위 고지 문장 유지.
3. Sophie에게 예행 요청 — 안건 경로는 **전체 경로**로(메신저엔 현재 폴더가 없음). Docker라면 컨테이너 안의 경로:
   `~/.hermes/workspace/magma-finance-lab/briefs/council-brief.md` (`$HERMES_HOME`이 다르면 그 경로)
4. 예행 여섯 항목 확인(패널 3·관점 3·턴 3·안건 읽힘·**결론 전 묻기 켜짐**·중계 채널) → "좋아, 이대로 열어줘."
5. 상태 확인 → 사람 결정(채택/보류/추가 검증 + 이유 한 문장)
6. 보고서 내보내기 + `reports/council` 사본

---

## 문제 → 원인 빠른 표 (Docker 추가분)

| 증상 | Docker에서의 원인 | 조치 |
| --- | --- | --- |
| 터미널에선 되는데 카드/크론/슬랙 Sam만 키움 인증 실패 | keyring 설정 파일이 HOME 밖이거나 백엔드 미설정 | 0-3, 8.1 보완 문서 |
| `kiwoomcli setup`이 keyring 백엔드 오류로 멈춤 | 컨테이너에 OS Keyring 없음 | 8.1 보완 문서 |
| 이미지 갱신 뒤 `kiwoomcli` 없음 | `~/.local`이 볼륨 밖 | 0-2 |
| Ada MCP `vibe-finance-kit` 연결 실패 | `.venv` 절대경로 유실 | 볼륨 확인 후 `setup_hermes.py` 재실행 |
| 크론이 9시간 어긋나 실행 | 컨테이너 TZ=UTC | 0-4 |
| `council doctor`에서 gateway 실패 | 다른 사용자/컨테이너의 게이트웨이 | 같은 사용자로 `hermes gateway status` |
| `setup_hermes.py`가 멈춤 | `-it` 없는 exec | 대화형 셸에서 실행 |
| `hermes`/`kiwoomcli` not found | 로그인 셸 아님 | `bash -l` 또는 PATH export |
