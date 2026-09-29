# 8.3 7단계 손 검산 도우미 (읽기 전용). magma-finance-lab 폴더에서 실행:
#   python3 handcheck_first_cycle.py [보고서 JSON] [스냅샷 JSON]
# 보고서의 첫 매수-매도 사이클을 원본 일봉 시가·종가와 나란히 보여 준다. 판정은 사람이 한다.
import json, sys
rep_path = sys.argv[1] if len(sys.argv) > 1 else "artifacts/backtest/calibration-069500-p08.json"
snap_path = sys.argv[2] if len(sys.argv) > 2 else "artifacts/market/market-snapshot-069500.json"
rep = json.load(open(rep_path))
rows = {r["trade_date"]: r for r in json.load(open(snap_path))["rows"]}
days = sorted(rows); nxt = {d: days[i + 1] for i, d in enumerate(days[:-1])}
fee, slip = rep["costs"]["fee_bps"], rep["costs"]["slippage_bps"]
p = rep["strategy"]["p_target"]; d_trig = rep["strategy"]["d_trigger"]
print(f"보고서: {rep_path}\n구간 {rep['test_period']['start']}~{rep['test_period']['end']}, 익절 {p}%, 추가매수 -{d_trig}%\n")
print(f"{'#':>2} {'신호일':10} {'신호일종가':>9} {'체결일':10} {'원본시가':>8} {'보고서시가':>8} 구분 수량 보유 {'평단(비용포함)':>13} {'평단x1.08':>10}  점검")
qty, cost, n = 0, 0.0, 0
for t in rep["result"]["trades"]:
    n += 1
    s, e = t["signal_date"], t["execution_date"]
    sc, o = rows[s]["close_price"], rows[e]["open_price"]
    avg_before = cost / qty if qty else 0.0
    checks = []
    checks.append("다음거래일OK" if nxt.get(s) == e else "다음거래일X")
    checks.append("시가일치" if o == t["execution_open"] else "시가불일치")
    if t["side"] == "BUY":
        fill = o * (1 + slip / 1e4); gross = fill * t["quantity"]
        cost += gross * (1 + fee / 1e4); qty += t["quantity"]
        if avg_before:
            if sc <= avg_before * (1 - d_trig / 100): checks.append("추가매수(-3%)발동")
    else:
        checks.append("매도조건OK" if sc >= avg_before * (1 + p / 100) else "매도조건X")
        qty -= t["quantity"]; cost = 0.0 if qty == 0 else cost * qty / (qty + t["quantity"])
    avg = cost / qty if qty else avg_before
    print(f"{n:>2} {s} {sc:>9,} {e} {o:>8,} {t['execution_open']:>8,} {t['side']:4} {t['quantity']:>3} {qty:>4} {avg:>13,.1f} {avg*(1+p/100):>10,.1f}  {' '.join(checks)}")
    if t["side"] == "SELL" and qty == 0:
        print("\n첫 사이클 종료 (전량 매도)."); break
