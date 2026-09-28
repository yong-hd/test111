# Hermes VPS / Docker — 자산운용팀 8.2 ~ 8.5 실습 보조

- `docs/hermes-vps-operations.md` — 이 VPS(Hostinger `hvps-hermes-agent`) 운영 기준: 접속·프로필·재시작·백업·보안
- `docs/hermes-docker-8.2-8.5.md` — 강의 가이드를 Docker 컨테이너에서 진행할 때 달라지는 점과 유닛별 순서
- `scripts/hermes-env.sh` — 호스트에서 `source`하면 `HC`와 도우미(`hsh`·`hx`·`hp`·`hlogs`·`hpre`) 설정
- `scripts/docker-preflight.sh` — VPS 호스트에서 실행하는 읽기 전용 점검 (볼륨·시간대·PATH·게이트웨이·Keyring·limits.md)

```bash
source scripts/hermes-env.sh
hpre
```

실습 저장소(magma-finance-lab)는 컨테이너 안 `~/.hermes/workspace/`에 있고, 이 저장소에는 비밀값·계좌 정보를 두지 않습니다.
