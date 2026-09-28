# Hermes VPS 운영 가이드 (Hostinger · Docker)

이 VPS에서 Hermes를 매일 다룰 때 쓰는 기준 문서입니다. 강의 가이드(8.2~8.5)의 명령을
**이 컨테이너에서 어떻게 실행하는지**를 정리하고, 유닛별 Docker 주의사항은
[`hermes-docker-8.2-8.5.md`](./hermes-docker-8.2-8.5.md)에 둡니다.

---

## 1. 내 환경

| 항목 | 값 | 비고 |
| --- | --- | --- |
| 호스트 | `srv1840967` | root로 접속 |
| 이미지 | `ghcr.io/hostinger/hvps-hermes-agent:latest` | Hostinger 제공 |
| 스택 폴더 | `/docker/hermes-agent-yx1l` | `docker-compose.yml` 위치 |
| 호스트 데이터 폴더 | `/docker/hermes-agent-yx1l/data` | 컨테이너 안 경로는 3장에서 확인 |
| 컨테이너 | `hermes-agent-yx1l-hermes-agent-1` | 재생성 시 이름 유지, 스크립트는 자동 탐지 |
| 포트 | `0.0.0.0:32773 → 4860` | **공인 IP에 공개**됨 (7장) |

2026-09-28 점검 결과:

| 항목 | 값 | 의미 |
| --- | --- | --- |
| 컨테이너 기본 사용자 | `root` | `docker exec` 기본값. **작업은 `-u hermes`로** |
| 게이트웨이 실행 사용자 | `hermes` (uid 10000, HOME `/opt/data`) | s6가 root로 띄운 뒤 hermes로 낮춰 실행 |
| 컨테이너 `HOME` | `/opt/data` | `~` = `/opt/data` |
| `HERMES_HOME` | `/opt/data` | 프로필·칸반·크론·스킬 전부 여기 |
| 볼륨 | `/docker/hermes-agent-yx1l/data -> /opt/data` | HOME 전체가 영속 — `~/.local`, keyring 파일 포함 |
| 시간대 | `UTC +0000` | **KST 아님** → 3-2 |
| `hermes` | `/opt/data/.local/bin/hermes` | 영속 |
| `uv` | `/usr/local/bin/uv` | 이미지에 포함 |
| `kiwoomcli` | `/opt/data/.local/bin/kiwoomcli` (kwcli 1.0.3) | 2026-09-28 설치, demo·모의계좌 인증 통과 (root·hermes 모두) |
| 강의 작업 폴더 | `/opt/data/.hermes/workspace/magma-finance-lab` | = 강의 경로 `~/.hermes/workspace/...` 그대로 |
| 프로필 | ada, ethan, iris, mia, noah, oliver, sam, sophie | 강의 5명 모두 있음 |
| 게이트웨이 | default 프로필 멀티플렉서, 실행 중 | 모든 프로필 카드·크론을 이것이 처리 |

호스트 ↔ 컨테이너 경로는 1:1입니다: `/docker/hermes-agent-yx1l/data/X` = 컨테이너 `/opt/data/X`.

--- | --- |
| 컨테이너 기본 사용자 (`whoami`) | |
| 컨테이너 `HOME` | |
| `HERMES_HOME` | |
| `data` 폴더의 컨테이너 안 경로 | |
| 시간대 (`date +%Z`) | |
| 프로필 목록 | |

---

## 2. 매 세션 시작 루틴

VPS에 SSH로 들어오면 먼저:

```bash
source /path/to/test111/scripts/hermes-env.sh
# [hermes-env] 컨테이너: hermes-agent-yx1l-hermes-agent-1
```

이 한 줄로 `HC`가 잡히고 아래 도우미가 생깁니다. 매번 치기 싫으면 `~/.bashrc` 끝에 같은 줄을 넣습니다.

| 도우미 | 하는 일 | 예 |
| --- | --- | --- |
| `hsh` | 컨테이너 안 로그인 셸 | `hsh` → `cd ~/.hermes/workspace/magma-finance-lab` |
| `hx '<명령>'` | 컨테이너 안 명령 한 줄 | `hx 'kiwoomcli doctor'` |
| `hp <프로필> <인자…>` | 그 프로필로 hermes 실행 | `hp sam`, `hp sophie council doctor` |
| `hlogs [줄수]` | 컨테이너 로그 따라보기 | `hlogs 300` |
| `hpre` | 읽기 전용 점검 (`docker-preflight.sh`) | `hpre` |

도우미 없이 쓸 때의 원형:

```bash
# 호스트 (root@srv1840967)
export HC=$(docker ps --format '{{.Names}}' | grep hermes-agent | head -1)
docker exec -it -u hermes "$HC" bash -l      # 프롬프트: hermes@<컨테이너ID>
```

규칙:
- **프롬프트로 위치를 구분합니다.** `root@srv1840967` = 호스트(`docker` 명령 가능), `…@e7788d11a4f7` 같은
  컨테이너 ID = 컨테이너 안(`docker` 명령 없음). 호스트용 명령을 컨테이너 안에서 치면 `No such container`가 납니다.
- **작업은 `-u hermes`로.** 게이트웨이(메신저·칸반 카드·크론)가 `hermes` 사용자로 돕니다. root로
  `kiwoomcli`·`git`·파일 생성을 하면 root 소유 파일이 생겨 게이트웨이가 못 읽거나 못 씁니다.
  root가 필요한 건 `chown`, 패키지 설치 같은 관리 작업뿐입니다.
- **root로 만든 파일이 생겼다면** 컨테이너 안 root 셸에서 `chown -R hermes:hermes <경로>`로 돌려놓습니다.
- **여러 줄을 붙여 넣을 때** 첫 줄이 `docker exec -it … bash -l`이면 나머지 줄은 버려집니다. 셸에 들어간 뒤 붙여 넣습니다.
- **대화형 명령은 `-it`** (`kiwoomcli setup`, `setup_hermes.py`의 Y/N 질문, `hermes -p sam` 채팅).

---

## 3. 처음 한 번: 환경 파악 (1장 표 채우기)

모두 읽기 전용입니다.

```bash
hx 'whoami; echo HOME=$HOME; echo HERMES_HOME=${HERMES_HOME:-미설정}; date "+%Z %z"'
docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' "$HC"
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$HC"
hx 'ls "${HERMES_HOME:-$HOME/.hermes}"; ls "${HERMES_HOME:-$HOME/.hermes}/profiles"'
cat /docker/hermes-agent-yx1l/docker-compose.yml     # 환경변수·볼륨·포트 확인 (비밀값은 공유하지 말 것)
hpre
```

판단 기준:
- `/docker/hermes-agent-yx1l/data -> X` 에서 **X가 `HERMES_HOME`(또는 `HOME`)을 포함**해야 합니다.
  아니라면 프로필·스킬·workspace·칸반이 컨테이너 안에만 있어 이미지 갱신 때 사라집니다.
- `HOME/.local`(kwcli, uv 도구)과 Keyring 폴더가 볼륨 밖이면 5장 업데이트 전에 조치가 필요합니다.
- 강의 가이드의 `~/.hermes/workspace/...`는 **`$HERMES_HOME/workspace/...`로 읽습니다.**
  두 값이 다르면 프롬프트 속 경로(예: 8.5의 안건 문서 전체 경로)도 실제 경로로 바꿔 넣습니다.

---

### 3-1. 강의 경로 `~/.hermes/workspace` — 이미 맞음

강의 문서와 스크립트는 `~/.hermes/workspace/magma-finance-lab`을 기준으로 씁니다.
이 컨테이너에서 `~` = `/opt/data`이고, `/opt/data/.hermes/workspace/magma-finance-lab`에 8.1에서 clone한
스타터가 있습니다(2026-09-28 확인). **강의 경로 그대로 쓰면 되고 링크를 만들 필요가 없습니다.**

- `/opt/data/.hermes`의 나머지(`.env`, `config.yaml`, `kanban.db` …)는 6~7월에 쓰던 **예전 Hermes 홈**입니다.
  건드리거나 지우지 않고, `HERMES_HOME`을 그쪽으로 바꾸지 않습니다. 특히 `.env`에는 예전 비밀값이 있을 수 있습니다.
- 현재 Hermes 본체(프로필·칸반·크론)는 `HERMES_HOME=/opt/data`입니다. 칸반 카드는 강의대로 workdir을
  `$HOME/.hermes/workspace/magma-finance-lab`(= 위 경로)로 고정하므로 서로 섞이지 않습니다.
- `/opt/data/workspace`는 비어 있으며 쓰지 않습니다.

### 3-2. 시간대를 KST로 — Hermes 설정으로 (적용 완료 2026-09-28)

컨테이너는 UTC지만, Hermes에는 `timezone` 설정이 있어 컨테이너를 재생성하지 않고 KST를 쓸 수 있습니다.
기본 프로필(게이트웨이·크론 스케줄러)과 Sam 프로필에 넣었습니다.

```bash
# 컨테이너 안, hermes 사용자 — 이미 있으면 건너뜀, 백업 후 끝에 한 줄 추가
for f in /opt/data/config.yaml /opt/data/profiles/sam/config.yaml; do
  grep -q "^timezone:" "$f" || { cp "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"; printf '\ntimezone: Asia/Seoul\n' >> "$f"; }
done
hermes -p sam config 2>&1 | grep -i timezone      # Timezone: Asia/Seoul
```

적용은 호스트에서 `docker restart "$HC"`. 크론을 쓰는 다른 프로필(Ada 품질 카드 등)에도 필요하면 같은 줄을 추가합니다.
크론 등록 후 "다음 실행 시각"이 KST인지 최종 확인합니다. `date`는 계속 UTC로 나오는 게 정상입니다.

### 3-2b. 8장 프로필 작업 폴더(cwd) — 변경 완료 2026-09-28

sam·ada·oliver의 `terminal.cwd`가 예전 홈(`/opt/data/.hermes/profiles/<이름>/workspace`)으로 고정되어 있어,
강의 요청문의 상대경로(`artifacts/…`, `scripts/…`)가 엉뚱한 폴더를 가리켰습니다. 8장 동안 스타터로 바꿨습니다.
기존 폴더의 파일(ada의 메모·복구 스크립트, oliver의 `company/`)은 그대로 남아 있습니다.

```bash
# 컨테이너 안, hermes 사용자
LAB=/opt/data/.hermes/workspace/magma-finance-lab
for p in sam ada oliver; do
  f=/opt/data/profiles/$p/config.yaml
  cp "$f" "$f.bak-cwd-$(date +%Y%m%d-%H%M%S)"
  sed -i "s#^  cwd: /opt/data/.hermes/profiles/$p/workspace\$#  cwd: $LAB#" "$f"
done
grep -n "^  cwd:" /opt/data/profiles/{sam,ada,oliver}/config.yaml
```

- noah(8.4)·sophie(8.5)도 해당 유닛 시작 전에 같은 방식으로 확인합니다.
- 되돌리기: `/opt/data/profiles/<이름>/config.yaml.bak-cwd-<날짜>`를 `config.yaml`로 복사.
- 게이트웨이(메신저·카드)에 반영하려면 호스트에서 `docker restart "$HC"` 후 30초 대기.

### 3-3. 점검 중 함께 보인 경고 (강의 전 정리 권장)

- **텔레그램 토큰 중복:** `default`와 `sophie`가 같은 `TELEGRAM_BOT_TOKEN`을 가지고 있어, 한쪽 어댑터는 쉬고 있습니다.
  8.5에서 Sophie(의장)의 회의 중계가 텔레그램으로 가야 한다면 문제가 됩니다. Sophie에게 별도 봇 토큰을 주거나,
  default의 `gateway.profile_routes`로 라우팅한 뒤 `hermes gateway migrate --multiplex`.
  (8.4 승인 루프처럼 슬랙을 쓴다면 당장 영향은 없습니다.)
- **`terminal.env_passthrough`가 문자열:** `config.yaml`에서 `'["BRIGHTDATA_API_KEY","BRIGHTDATA_UNLOCKER_ZONE"]'` 따옴표를 빼고
  YAML 리스트로 바꿔야 적용됩니다. `hermes doctor`가 수정 방법을 알려 줍니다. 강의와 직접 관계는 없습니다.

## 4. 프로필

### `profile use` 대신 `-p`

```bash
docker exec "$HC" hermes profile use mia     # 전역 기본 프로필이 바뀜
hp mia                                        # 이번 실행만 mia
```

`profile use`는 **이후의 모든 기본값**을 바꿉니다. 게이트웨이·크론·다른 터미널이 기본 프로필을 참조하면
의도치 않게 영향을 받습니다. 강의 명령도 전부 `hermes -p <프로필>` 형태이므로 `hp`를 기본으로 씁니다.
기본 프로필은 평소 쓰는 비서(예: mia)로 고정해 두고 바꾸지 않습니다.

### 강의 프로필 준비

| 프로필 | 역할 | 첫 사용 |
| --- | --- | --- |
| `sam` | 개발·수집·집행 (키움 CLI) | 8.1 |
| `ada` | 분석·검증·Supabase MCP | 8.2 |
| `oliver` | 공개자료 리서치 (주문 도구 없음) | 8.2 |
| `noah` | 하루 보고 (DB 접근 없음) | 8.4 |
| `sophie` | 투자위원회 의장 (council 플러그인) | 8.5 |

`hx 'ls "${HERMES_HOME:-$HOME/.hermes}/profiles"'`로 없는 것만 만듭니다. 이름이 다르면 `setup_hermes.py`의
`--ada-profile` / `--oliver-profile`로 맞출 수 있지만, 프롬프트 속 이름까지 바꿔야 하므로 **강의 이름 그대로 만드는 편이 쉽습니다.**

---

## 5. 일상 운영

### 상태 보기

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep hermes
hx 'hermes gateway status'
hlogs 200
```

### 재시작 종류 (결과가 다릅니다)

| 명령 | 컨테이너 | 볼륨 밖 파일 | 언제 |
| --- | --- | --- | --- |
| `docker restart "$HC"` | 유지 | 유지 | 게이트웨이가 이상할 때 |
| `cd /docker/hermes-agent-yx1l && docker compose up -d` (설정 변경 시) | **재생성** | **유실** | compose 수정 후 |
| `docker compose pull && docker compose up -d` | **재생성** | **유실** | 이미지 업데이트 |

### 재시작 뒤 체크리스트 (매번)

1. `hx 'hermes gateway status'` — 게이트웨이 실행 중
2. `hx "kiwoomcli auth status --profile 모의계좌"` — `토큰 유효`, `지금 API 호출 가능`이 `예`
   (실패하면 `~/.config/python_keyring/keyringrc.cfg`가 있는지부터 — 8.1 보완 문서)
3. 슬랙에서 Sam에게 한 줄 질문 → 응답 오는지
4. 크론 목록에서 다음 실행 시각·시간대 확인 (8.2 18:30, 8.4 08:40)

### 업데이트 전 백업

```bash
cd /docker/hermes-agent-yx1l
tar czf /root/hermes-data-$(date +%Y%m%d-%H%M).tgz data docker-compose.yml
docker compose pull && docker compose up -d
source /path/to/test111/scripts/hermes-env.sh     # HC 재확인
hpre
```

백업 파일에는 Keyring·토큰이 들어 있을 수 있으니 VPS 밖으로 옮길 때 주의합니다.

---

## 6. 파일을 사람이 직접 고칠 때

강의에는 사람이 직접 고치는 파일이 있습니다: `guardrails/limits.md`(status: confirmed),
`backtest/rules.md` 근거 칸, `briefs/council-brief.md`.

- **컨테이너 안에서:** `hsh` → `nano guardrails/limits.md` (편집기가 없으면 아래 방법)
- **호스트에서:** 3장에서 확인한 매핑대로 `/docker/hermes-agent-yx1l/data/...` 아래 파일을 편집
  - 편집 뒤 `ls -ln`으로 소유자 UID가 그대로인지 확인합니다. 호스트 root가 새 파일을 만들면
    컨테이너 사용자가 쓰지 못할 수 있습니다(`cp`로 만드는 `council-brief.md`는 **컨테이너 안에서** 복사).
- git 작업(`git pull --ff-only`, 병합)은 항상 컨테이너 안에서 합니다. 호스트와 컨테이너의 git 사용자가
  달라 `dubious ownership` 오류가 날 수 있습니다.

---

## 7. 보안

- **포트 `0.0.0.0:32773 → 4860`이 인터넷에 열려 있습니다.** 4860이 무엇인지(대시보드/웹 UI)와
  로그인 보호 여부를 먼저 확인하세요. 칸반 대시보드나 게이트웨이 API라면:
  - Hostinger 패널에서 방화벽으로 본인 IP만 허용하거나,
  - compose의 포트를 `127.0.0.1:32773:4860`으로 바꾸고 `ssh -L 32773:localhost:32773 root@srv1840967`로 접속
  - Hostinger 패널 기능이 이 포트에 의존하는지 먼저 확인한 뒤 바꿉니다.
- 키움 App Key·Secret, Supabase 키, 계좌번호는 이 저장소·채팅·로그에 남기지 않습니다.
  `docker-compose.yml`이나 `docker inspect` 출력을 공유할 때 `Env` 줄은 지웁니다.
- 실계좌를 `kiwoomcli setup`에 등록하지 않습니다. 이 VPS는 `demo` 모의계좌 전용입니다.

---

## 8. 자주 쓰는 명령 모음

```bash
source /path/to/test111/scripts/hermes-env.sh     # 세션 시작
hpre                                              # 전체 점검
hsh                                               # 컨테이너 셸
hp sam                                            # Sam 대화
hx 'cd ~/.hermes/workspace/magma-finance-lab && git pull --ff-only'
hx 'kiwoomcli auth status --profile 모의계좌'
hx 'hermes gateway status'
hp sophie council doctor
hlogs 200
docker restart "$HC"
```
