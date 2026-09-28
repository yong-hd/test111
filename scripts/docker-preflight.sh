#!/usr/bin/env bash
# Hermes Docker 환경 사전 점검 (8.2~8.5 공통). 읽기 전용이며 아무것도 변경하지 않는다.
# VPS 호스트에서 실행한다:
#   ./scripts/docker-preflight.sh                      (hermes-agent 컨테이너 자동 탐지)
#   HERMES_CONTAINER=<이름> HERMES_USER=<사용자> ./scripts/docker-preflight.sh
# 비밀값·토큰·계좌번호는 출력하지 않는다. kiwoomcli auth status는 지정한 항목 줄만 옮긴다.
set -u

C="${HERMES_CONTAINER:-${HC:-$(docker ps --format '{{.Names}}' | grep hermes-agent | head -1)}}"
U="${HERMES_USER:-}"
PROFILE="${KIWOOM_PROFILE:-모의계좌}"

ok()   { printf '  [OK]   %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; }

echo "== 0. 컨테이너"
if ! docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null | grep -q true; then
  fail "컨테이너 '$C'가 실행 중이 아님 (HERMES_CONTAINER로 이름 지정)"; exit 1
fi
ok "컨테이너 '$C' 실행 중 (restart policy: $(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$C"))"

x() { if [ -n "$U" ]; then docker exec -u "$U" "$C" bash -lc "$1"; else docker exec "$C" bash -lc "$1"; fi; }

CHOME="$(x 'echo $HOME')"
HH="$(x 'echo ${HERMES_HOME:-$HOME/.hermes}')"
echo "  사용자: $(x whoami)  HOME=$CHOME  HERMES_HOME=$HH"

echo "== 0b. 외부 노출 포트"
docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}} <- {{.HostIp}}:{{.HostPort}}{{"\n"}}{{end}}{{end}}' "$C" | while IFS= read -r l; do
  [ -z "$l" ] && continue
  case "$l" in *"<- 127.0.0.1:"*|*"<- ::1:"*) ok "$l";; *) warn "$l — 모든 인터페이스에 공개됨. 방화벽/인증 확인, 가능하면 127.0.0.1 바인딩 + SSH 터널";; esac
done

echo "== 1. 영속 볼륨 (컨테이너 재생성 시 사라지면 안 되는 경로)"
docker inspect -f '{{range .Mounts}}    {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' "$C"
MOUNTS="$(docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$C")"
for p in "$HH" "$CHOME/.local" "$CHOME/.local/share/keyrings"; do
  hit=""
  while IFS= read -r m; do
    [ -n "$m" ] && case "$p/" in "$m"/*) hit="$m";; esac
  done <<< "$MOUNTS"
  if [ -n "$hit" ]; then ok "$p  ← 볼륨 $hit"; else warn "$p 가 볼륨 밖 — 재생성(docker compose up --force-recreate/이미지 갱신) 시 유실"; fi
done

echo "== 2. 시간대 (크론 8:40 / 18:30 기준)"
TZNOW="$(x 'date "+%Z %z"')"
case "$TZNOW" in *+0900*) ok "컨테이너 시간대 $TZNOW";; *) warn "컨테이너 시간대 $TZNOW — TZ=Asia/Seoul 아님. 크론 등록 시 다음 실행 시각의 시간대를 반드시 확인";; esac

echo "== 3. 실행 파일 (로그인 셸 PATH 기준)"
for b in hermes uv kiwoomcli git python3; do
  path="$(x "command -v $b" 2>/dev/null)"
  if [ -n "$path" ]; then ok "$b → $path"; else fail "$b 없음 (export PATH=\"\$HOME/.local/bin:\$PATH\" 확인)"; fi
done

echo "== 4. 게이트웨이 (칸반 디스패치·슬랙·council 필수)"
GW="$(x 'hermes gateway status' 2>&1 | head -20)"
printf '%s\n' "$GW" | sed 's/^/    /'
GWPID="$(x 'pgrep -f "gateway" | head -1' 2>/dev/null)"
if [ -n "$GWPID" ]; then
  ok "게이트웨이 프로세스 PID $GWPID"
  # 게이트웨이/크론 프로세스가 Keyring(Secret Service)에 닿는지: DBus 주소와 TZ 존재 여부만 확인
  GENV="$(x "tr '\0' '\n' < /proc/$GWPID/environ" 2>/dev/null)"
  if printf '%s\n' "$GENV" | grep -q '^DBUS_SESSION_BUS_ADDRESS='; then ok "게이트웨이 환경에 DBUS_SESSION_BUS_ADDRESS 있음"
  else warn "게이트웨이 환경에 DBUS_SESSION_BUS_ADDRESS 없음 — 카드/크론에서 kiwoomcli가 Keyring을 못 찾을 수 있음 (런북 0-3 참고)"; fi
  printf '%s\n' "$GENV" | grep -q '^TZ=' && ok "게이트웨이 $(printf '%s\n' "$GENV" | grep '^TZ=')" || warn "게이트웨이 환경에 TZ 미설정"
else
  warn "pgrep로 게이트웨이 프로세스를 찾지 못함 — 위 status 출력으로 판단 (멈춰 있으면 카드가 ready에서 멈춤). Keyring·TZ 환경 확인은 건너뜀"
fi

echo "== 5. 키움 모의계좌 인증 (지정 항목만)"
x "kiwoomcli auth status --profile '$PROFILE'" 2>&1 \
  | grep -E '계좌 별칭|모드|자격 증명 존재|자격 증명 출처|토큰 유효|지금 API 호출 가능' \
  | sed 's/^/    /' || fail "auth status 실패"

echo "== 6. 작업 폴더"
W="$HH/workspace"
x "test -d '$W'" || { x "test -d '$CHOME/.hermes/workspace'" && W="$CHOME/.hermes/workspace"; }
echo "  workspace: $W"
for d in magma-finance-lab vibe-finance-kit; do
  if x "test -d '$W/$d'"; then ok "$W/$d"; else warn "$W/$d 없음"; fi
done
if x "test -d '$W/magma-finance-lab'"; then
  R="$(x "git -C '$W/magma-finance-lab' remote -v")"
  [ -z "$R" ] && ok "magma-finance-lab: git remote 없음(스타터 권장)" || warn "magma-finance-lab: remote 있음 → git pull --ff-only 가능, push는 금지"
  ST="$(x "sed -n 's/^status: *//p' '$W/magma-finance-lab/guardrails/limits.md' | head -1")"
  [ "$ST" = confirmed ] && ok "limits.md status: confirmed" || warn "limits.md status: ${ST:-?} — 8.4 기안이 차단됨 (사람이 직접 확정)"
  x "test -f '$W/magma-finance-lab/artifacts/setup/setup-receipt-vibe-finance-kit.json'" \
    && ok "vibe-finance-kit 설치 영수증 있음" || warn "설치 영수증 없음 (8.2 3단계 전이면 정상)"
fi

echo "== 7. 프로필"
x 'hermes profile list 2>/dev/null || ls "${HERMES_HOME:-$HOME/.hermes}/profiles" 2>/dev/null' | sed 's/^/    /'
x 'hermes profile show 2>/dev/null | head -5' | sed 's/^/    현재 기본 프로필: /'
echo "  필요: sam, ada, oliver (8.2) · noah (8.4) · sophie (8.5)"
