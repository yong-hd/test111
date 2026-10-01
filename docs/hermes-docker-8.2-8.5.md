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

### 8.2 보충 — Ada에 Supabase MCP 연결 (이 VPS, 2026-09-28)

7장을 건너뛰어 Supabase 프로젝트와 Ada 연결이 없었습니다. 새 프로젝트(Free, Seoul)를 만들고 원격 MCP를
**PAT + 헤더 인증**으로 붙였습니다(컨테이너에 브라우저가 없어 OAuth 대신).

```bash
# 컨테이너 안, hermes 사용자 — 한 줄씩, 프롬프트가 돌아온 뒤 다음 줄
read -r -p "Supabase Reference ID: " REF; REF=$(printf '%s' "$REF" | tr -d '[:space:]')
read -r -s -p "Supabase PAT (sbp_...): " TK; echo; TK=$(printf '%s' "$TK" | tr -d '[:space:]')
printf 'MCP_SUPABASE_API_KEY=%s\n' "$TK" >> /opt/data/profiles/ada/.env; chmod 600 /opt/data/profiles/ada/.env; unset TK
hermes -p ada mcp add supabase --url "https://mcp.supabase.com/mcp?project_ref=${REF}&features=database,debugging,docs" --auth header
```

- `project_ref`로 이 프로젝트 하나에만, `features`로 DB·진단·문서 도구 8개만 엽니다(스토리지·함수·브랜치·계정 도구 없음).
- 토큰은 `/opt/data/profiles/ada/.env`(600)에만 있고 `config.yaml`에는 변수 이름만 들어갑니다.
- **함정:** 가려진 입력창에 여러 번 붙여 넣으면 토큰이 반복 저장됩니다(길이 44의 배수). `grep -o sbp_ | wc -l`로 확인.
  `hermes mcp add`의 인증 질문에서 `Ctrl+C`는 중단되지 않고 다음 질문(토큰)으로 넘어가므로, 실수했으면 끝까지 가서 `Save config anyway? → N` 후 `.env`의 `MCP_SUPABASE_API_KEY` 줄을 지웁니다.
- 폐기: Supabase 콘솔 Access Tokens에서 해당 토큰 Revoke.

### 8.2 보충 — 칸반 진행 기록 (이 VPS, 2026-09-29~30)

보드 `asset-management-market-data`, workdir `/opt/data/.hermes/workspace/magma-finance-lab`(dir).

| 카드 | 담당 | 결과 |
|---|---|---|
| t_77df475a 수집 | sam | 종목별 3,000봉, 2014-07-08~2026-09-29, 공통 3,000, gate_passed |
| t_875ee2ca 조사 | oliver | 추적오차·괴리율·TIGER 순자산·KOSPI200 PER/PBR 등 7개 null(공식 사이트 403/Service unavailable) |
| t_937b10a4 품질 | ada | 5개 항목 PASS |
| t_7ebe10e3 적재 | ada | daily_prices 6,000행 적재·재검산 0건 |

이 버전의 Hermes에서 달라진 점:
- **강의 요청문의 `$HOME/...` 경로는 쓰지 않습니다.** 에이전트 터미널의 `$HOME`은 프로필 전용 폴더라 workdir이 엉뚱해집니다. 절대경로를 씁니다.
- **새 보드를 만든 세션은 옛 보드에 고정**(`HERMES_KANBAN_BOARD`)되어 있을 수 있습니다. 카드는 새 세션에서, 보드 slug를 명시해 만듭니다.
- **workspace 방식은 카드마다 `workspace_kind=dir`로 명시**합니다(보드 기본 workdir은 경로만 정함).
- **done 카드는 재실행되지 않습니다.** 강의처럼 품질 카드에 "대표 적재 승인" 댓글을 달아도 적재가 시작되지 않으므로, 품질 카드에 의존하는 **Ada 적재 카드를 새로** 만들어 승인 댓글 후 dispatch했습니다.
- 적재 담당은 **Ada**입니다(Supabase MCP가 Ada에만 있음). Sam이 AGENTS.md 역할표를 근거로 Sam 배정을 제안하면 PROMPTS.md "4. …적재하고 검산하기 (Ada)"를 근거로 Ada로 지정합니다.
- 수집 결과의 마지막 날짜는 **실행 시각(KST) 기준 전날**입니다. `price-history-coverage.json`의 `generated_at`으로 판단합니다.

### 8.2 보충 — 매일 수집 크론 (이 VPS)

- cron `b051cb7d7538`: 평일 18:30 Asia/Seoul, profile sam, workdir `/opt/data/.hermes/workspace/magma-finance-lab`
- 명령: `python3 scripts/backfill_prices.py --pages 1 --minimum-common-bars 1 --output-dir artifacts/market-daily`
  → 이어서 Ada 가격 품질 카드(입력 `artifacts/market-daily/`).
- **주의:** 기본 출력(`artifacts/market/`)으로 `--pages 1`을 돌리면 스냅샷을 600봉으로 **먼저 덮어쓴 뒤**
  2,500봉 게이트에서 실패합니다. `artifacts/market/`의 3,000봉 스냅샷은 8.3 백테스트 입력이므로 매일 크론은 별도 폴더에 씁니다.
- 매일 수집분의 Supabase 적재는 강의 크론 범위 밖입니다(수집 + 품질 검증까지).
- 정리: 운영을 멈출 때 Sam에게 cron ID로 삭제를 요청하고 목록에서 사라졌는지 확인.

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

### 8.3 진행 기록 (이 VPS, 2026-09-30)

| 단계 | 결과 |
|---|---|
| 준비물 대조 | 공통 2014-07-08~2026-09-29 3,000일, Supabase 누락 0, 날짜 해시 일치 |
| 보정(2014-07-08~2020-12-30) | 5·8·12% → 212.3만·210.9만·213.4만원(초기 200만), 차이 ~1.2% |
| 평가(2021-01-04~2026-09-29, 8% 1회) | 251.3만 vs 일괄매수 552.3만, -150.5%p, MDD -19.4%, 미청산 10주 |
| 손 검산(보정 8% 첫 사이클) | 07-09~07-22 1주씩 10주, 추가매수 0회, 2017-04-25 종가 27,336 ≥ 27,155.3 → 04-26 시가 27,430 전량 매도. 4지점 일치 |
| 세 구간 | 2020-04~2021-06 -89%p(5사이클) · 2021-07~2022-10 +25%p(0사이클) · 2023 -22%p(1사이클) |
| 감사 | 경고 `one_cycle_hand_check_not_confirmed` → 검산 기록 후 `decision_eligible: true` |
| rules.md | P_TARGET·D_TRIGGER 근거 칸을 사람이 기록 |

이 VPS에서 다른 점:
- 강의 영상의 보정 시작일 `2014-05-19` 대신 **`2014-07-08`**(수집일이 달라 3,000봉 창이 이동). 처음부터 이 날짜로 지시하면 재실행 단계가 필요 없습니다.
- 모델 구독 한도(HTTP 429)에 걸리면 에이전트가 멈춥니다. 손 검산은 `scripts/handcheck_first_cycle.py`(이 저장소)로 사람이 직접 할 수 있습니다.
  `hermes fallback add`로 백업 제공자를 두면 크론·카드가 멈추지 않습니다.
- 컨테이너 셸이 `/opt/hermes`에서 시작하므로 상대경로 명령 전에 `cd /opt/data/.hermes/workspace/magma-finance-lab`
  (또는 `docker exec -it -u hermes -w /opt/data/.hermes/workspace/magma-finance-lab "$HC" bash -l`).

## 8.4 아침 주문 루프 (Docker 순서)

### 8.4 준비 — 메신저에서 Sam 부르기 (이 VPS: 텔레그램 FAT 그룹, 2026-09-30)

강의의 슬랙 `@Sam` 대신 **텔레그램 그룹 FAT**(`chat_id -5582644225`)을 Sam으로 라우팅했습니다. 봇은 기존 기본 프로필 봇(`@DyonHermes_Bot`) 그대로입니다.

```yaml
# /opt/data/config.yaml (기본 프로필) — profile_routes 아래
  - name: telegram-fat-to-sam
    platform: telegram
    chat_id: "-5582644225"
    profile: sam
```

- 그룹 ID 찾기: 그룹에서 봇을 멘션해 한 번 보낸 뒤 `/opt/data/channel_directory.json` 또는 `logs/gateway*.log`의 `chat=-…`.
- 적용: 호스트에서 `docker restart "$HC"` 후 **60초 이상** 대기(40초에는 아직 not running일 수 있음).
- 확인: FAT에서 `@DyonHermes_Bot … echo "HERMES_HOME=$HERMES_HOME"` → `/opt/data/profiles/sam` ✓
- 그룹에서는 봇을 **멘션**해야 메시지를 받습니다(텔레그램 봇 기본 privacy). 강의의 `@Sam 승인` → `@DyonHermes_Bot 승인`.
- 개인 DM과 다른 그룹(DyonHermesBot)은 기존대로 기본 프로필이 받습니다.
- 되돌리기: `/opt/data/config.yaml.bak-route-<날짜>` 복원 후 재시작.
- **승인 요청 전송:** `hermes -p sam send`는 Sam 프로필에 텔레그램 토큰이 없어 실패합니다.
  `hermes -p default send -t telegram:-5582644225 "…"`로 보냅니다(같은 봇이라 그룹에서는 동일하게 보임). SOUL 규칙에 이 명령을 적습니다.
- **Sam에도 Supabase MCP 연결:** 판단 루프 2번(`finance.orders`에 drafted 기록)을 Sam이 하므로 Ada와 같은 프로젝트·기능 범위로 추가.
  토큰은 `grep '^MCP_SUPABASE_API_KEY=' ada/.env >> sam/.env` 로 화면 출력 없이 복사 후 `hermes -p sam mcp add supabase … --auth header`.
- **준비 점검 결과(2026-09-30):** Sam preflight 통과(limits confirmed·템플릿 존재) · Ada 주문 도구 없음(분석·Supabase만) · Noah 주문·DB 도구 없음
  · `TZ=Asia/Seoul python3 broker/decide.py --dry-run` → 2026-09-30, 109,545원, 보유 0 → BUY 1주(판단 파일 미생성).
- **실행은 장중에:** 장 마감 후에도 당일 종가로 판단이 나오지만 승인 후 집행은 장중이어야 하고 승인 만료가 약 10분입니다.
  드라이런 없이 한 번 돌리면 그날 판정 기록이 생겨 재기안이 막힙니다.
- **격리 한계:** kiwoomcli와 키 파일이 같은 `hermes` 사용자 소유라 Ada·Noah 터미널에서도 기술적으로는 닿을 수 있습니다(강의 PROMPTS 8.1-5와 같은 한계).
  PATH·스킬·SOUL·승인 카드로 역할을 나누며, 그래서 모의계좌만 씁니다.
- noah의 `terminal.cwd`도 magma-finance-lab으로 변경(sam·ada·oliver와 동일, 백업 `.bak-cwd-*`).


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

### 8.4 진행 기록 (이 VPS, 2026-10-01)

| 시각(KST) | 채널 | 일 |
|---|---|---|
| 15:05 | 텔레그램 FAT | 판단 루프 요청 → `decide.py`(**TZ 없이** 실행됨), BUY 1주 기준가 111,275 |
| 15:10 | → 슬랙 | 승인 요청이 슬랙으로 발송(옛 스킬대로), DB `finance.orders` id 1 drafted, 카드 `t_dcd774dd` blocked |
| 15:10→15:11 | 슬랙 | 사람 **보류** → 카드 blocked 유지·사유 기록(정상 동작) |
| 15:12 | 텔레그램 FAT | 사람 **승인** → unblock·dispatch |
| 15:16~17 | | 재검사 +0.07%(±1.5% 이내) → 1주 111,340원 체결, 수수료 380원, DB executed |
| 20:03 | 슬랙 | 대사: 기안·주문·체결·보유 1주 일치(MATCHED) |
| 20:16 | 슬랙 | "한 번 더" → `오늘 이미 판정함` (중복 방지 ✓) |
| 20:18 | 슬랙 | 크론 `09971d8a1452` 평일 08:40 Asia/Seoul, 다음 2026-10-02 08:40 KST |

배운 점:
- 승인 채널이 둘(텔레그램·슬랙)이면 Sam 세션이 둘이 되어 서로의 대화를 모릅니다. 카드만 공유. → **슬랙 단일 채널**로 통일, FAT 라우팅 제거.
- Sam은 sam 프로필에 슬랙 토큰이 있어 슬랙에서 직접 응답합니다(`gateway status` 화면에는 안 보였음). Ada·Noah·Mia·Ethan도 프로필별 슬랙 토큰 보유.
- 자동 생성 스킬(`magma-order-approval-loop`)이 SOUL과 어긋날 수 있습니다. SOUL을 바꾼 뒤 스킬도 맞춥니다(TZ·채널).
- 장중(15:06)에 돌리면 `decide.py`가 장중가로 판단합니다. 강의 의도(직전 확정 종가)는 08:40 크론에서 맞습니다.
- Sam이 승인 만료를 15:30(장 마감)으로 잡았습니다. 템플릿 권장은 10분 안팎 → 다음 기안에서 확인.

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

### 8.5 진행 기록 (이 VPS, 2026-10-01)

- council 0.13.0을 sophie에만 설치, `council doctor` 4항목 통과. sophie `terminal.cwd`도 magma-finance-lab으로 변경.
- **첫 예행 요청에서 Sophie가 플러그인을 쓰지 않고** `hermes -p <패널> -z`로 직접 부르는 회의를 설계함 → 거절하고
  `/council …` 슬래시로 다시 요청하니 `council start --dry-run … --hitl --no-relay` 로 플러그인 예행.
- 회의 `kodex200-dca-review`(보드 `council-kodex200-dca-review`): ada → oliver → noah 각 1발언(max_turns 3 = 발언 3개), 약 16분.
- **HITL 게이트 미작동:** HITL은 코드 게이트가 아니라 의장 카드에 주는 지시문(`## [결정 요청]` 작성 후 정지)이라,
  의장 카드가 FINAL을 바로 쓰면 `pending_decision`이 뜨지 않습니다. 회의 결론은 루프에 자동 반영되지 않으므로 사람 결정은 그대로 유효.
- 패널 합의: 채택 지지 없음, BacktestReport draft, 낙폭 -40.81% 미검증. 갈린 점: 보류+추가검증(Noah·의장) vs 추가검증만.
- Oliver가 안건의 "8개 vs 이름 7개" 불일치를 지적 → 8번째는 `index_valuation_method`(안건 초안 누락, 스냅샷은 정합).
- 중계는 끔(안건에 평단·한도 수치). 산출물: `/opt/data/profiles/sophie/.council/kodex200-dca-review/{summary,report,decisions,transcript.export}.md`
- 결정이 `보류`이면 08:40 판단 루프 크론(`09971d8a1452`)을 **사람이 직접** 멈춰야 합니다(자동 반영 없음).

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