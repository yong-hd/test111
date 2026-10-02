# Hermes VPS 셸 도우미. VPS 호스트에서 매 세션 시작 시:
#   source /path/to/scripts/hermes-env.sh
# (영구 적용: ~/.bashrc 끝에 같은 source 줄을 추가)

export HERMES_STACK_DIR="${HERMES_STACK_DIR:-/docker/hermes-agent-yx1l}"   # docker-compose.yml 위치
export HERMES_DATA_DIR="${HERMES_DATA_DIR:-$HERMES_STACK_DIR/data}"         # 호스트 쪽 데이터 폴더
export HC="$(docker ps --format '{{.Names}}' | grep hermes-agent | head -1)"

if [ -z "$HC" ]; then
  echo "[hermes-env] 실행 중인 hermes-agent 컨테이너가 없습니다. cd \$HERMES_STACK_DIR && docker compose up -d" >&2
else
  echo "[hermes-env] 컨테이너: $HC"
fi

# 컨테이너 안 대화형 셸 (로그인 셸이라 ~/.local/bin이 PATH에 잡힘)
export HERMES_USER="${HERMES_USER:-hermes}"   # 게이트웨이 실행 사용자. root로 작업하면 root 소유 파일이 생김
hsh()  { docker exec -it -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 -u "$HERMES_USER" "$HC" bash -l; }
# 관리용 root 셸 (chown, 패키지 설치 등)
hroot(){ docker exec -it -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 "$HC" bash -l; }
# 컨테이너 안에서 명령 한 줄:  hx 'kiwoomcli doctor'
hx()   { docker exec -it -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 -u "$HERMES_USER" "$HC" bash -lc "$*"; }
# 특정 프로필로 hermes 실행 (전역 기본 프로필을 바꾸지 않음):  hp sam chat   /  hp sophie council doctor
hp()   { local p="$1"; shift; docker exec -it -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 -u "$HERMES_USER" "$HC" bash -lc 'hermes -p "$0" "$@"' "$p" "$@"; }
# 로그
hlogs(){ docker logs --tail "${1:-200}" -f "$HC"; }
# 읽기 전용 점검
hpre() { HERMES_CONTAINER="$HC" HERMES_USER="$HERMES_USER" "$(dirname "${BASH_SOURCE[0]}")/docker-preflight.sh"; }
