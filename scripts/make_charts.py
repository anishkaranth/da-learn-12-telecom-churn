#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S

RED, BLUE, GREEN, GREY = S.PALETTE[1], S.PALETTE[0], S.PALETTE[2], S.PALETTE[4]


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def heat(rate, avg):
    """Bar colour: red above the overall churn rate, blue at or below it."""
    return RED if rate > avg else BLUE


def panels(t):
    k = rd(t, "a_kpi_headline")[0]
    avg = f(k["churn_rate_pct"])
    con = sorted(rd(t, "a_churn_by_contract"), key=lambda r: f(r["contract_term_months"]))
    ten = sorted(rd(t, "a_churn_by_tenure_band"), key=lambda r: r["tenure_band"])
    mon = sorted(rd(t, "a_churn_by_tenure_month"), key=lambda r: int(r["tenure_months"]))
    coh = rd(t, "a_cohort_tenure_contract")
    years = sorted({r["tenure_year"] for r in coh})
    cv = {(r["tenure_year"], r["contract"]): f(r["churn_rate_pct"]) for r in coh}
    pay = sorted(rd(t, "a_churn_by_payment"), key=lambda r: -f(r["churn_rate_pct"]))
    net = sorted(rd(t, "a_churn_by_internet"), key=lambda r: -f(r["churn_rate_pct"]))
    add = sorted(rd(t, "a_churn_by_addon"), key=lambda r: f(r["churn_diff_pp"]))
    acnt = sorted(rd(t, "a_churn_by_addon_count"), key=lambda r: int(r["addon_count"]))
    drv = sorted(rd(t, "a_churn_drivers"), key=lambda r: -f(r["churn_diff_pp"]))
    mat = sorted(rd(t, "a_contract_internet_matrix"), key=lambda r: -f(r["mrr_lost"]))
    dem = {(r["dimension"], r["value"]): r for r in rd(t, "a_churn_by_demographics")}
    rev = {r["status"]: r for r in rd(t, "a_revenue_summary")}
    m1 = [r for r in mon if int(r["tenure_months"]) >= 1]
    dims = ["Senior citizen", "Partner", "Dependents"]
    return [
        ("churn_by_contract", S.vbar("Churn rate by contract type (%)", [r["contract"] for r in con],
                                     [f(r["churn_rate_pct"]) for r in con], "{:.1f}%",
                                     f"month-to-month = {f(con[0]['customer_share_pct']):.0f}% of customers but "
                                     f"{f(con[0]['churner_share_pct']):.1f}% of churners and {f(con[0]['mrr_lost_share_pct']):.1f}% of MRR lost",
                                     color=[heat(f(r["churn_rate_pct"]), avg) for r in con],
                                     notes=[f"n={int(f(r['customers'])):,}, ${f(r['mrr_lost']) / 1e3:,.1f}k MRR lost" for r in con],
                                     ylabel="churn rate %", vmax=50)),
        ("churn_by_tenure_band", S.vbar("Churn rate by tenure band (%)", [r["tenure_band"][2:] for r in ten],
                                        [f(r["churn_rate_pct"]) for r in ten], "{:.1f}%",
                                        f"median tenure: churned {f(k['median_tenure_churned']):.0f} months vs retained "
                                        f"{f(k['median_tenure_retained']):.0f}; red = above the {avg:.1f}% average",
                                        color=[heat(f(r["churn_rate_pct"]), avg) for r in ten],
                                        notes=[f"n={int(f(r['customers'])):,}" for r in ten], ylabel="churn rate %", vmax=60)),
        ("churn_curve_by_tenure_month", S.line("Churn rate by tenure month (1-72)", [r["tenure_months"] for r in m1],
                                               [("churn rate %", [f(r["churn_rate_pct"]) for r in m1]),
                                                ("month-to-month share %", [f(r["month_to_month_pct"]) for r in m1])], "{:.0f}",
                                               f"month 1: {f(m1[0]['churn_rate_pct']):.1f}% of {int(f(m1[0]['customers']))} customers churned; "
                                               "the contract mix shifts from monthly to term contracts with tenure", every=6, ymin=0)),
        ("cohort_tenure_contract", S.line("Churn by tenure year, split by contract (%)", years,
                                          [(c, [cv.get((y, c), 0) for y in years]) for c in ["Month-to-month", "One year", "Two year"]],
                                          "{:.0f}", "tenure lowers churn inside every contract, but monthly contracts stay far above term contracts",
                                          ymin=0, xlabel="tenure year")),
        ("churn_by_payment", S.hbar("Churn rate by payment method (%)", [r["payment_method"] for r in pay],
                                    [f(r["churn_rate_pct"]) for r in pay], "{:.1f}%",
                                    "electronic check is the highest-churn method; automatic payment roughly halves churn",
                                    color=[heat(f(r["churn_rate_pct"]), avg) for r in pay],
                                    notes=[f"n={int(f(r['customers'])):,}, ${f(r['mrr_lost']) / 1e3:,.1f}k MRR lost" for r in pay], vmax=60, h=220)),
        ("churn_by_internet", S.vbar("Churn rate by internet service (%)", [r["internet_service"] for r in net],
                                     [f(r["churn_rate_pct"]) for r in net], "{:.1f}%",
                                     f"fiber customers pay ${f(net[0]['avg_monthly_charges']):.2f}/month on average and carry "
                                     f"{f(net[0]['mrr_lost_share_pct']):.1f}% of MRR lost",
                                     color=[heat(f(r["churn_rate_pct"]), avg) for r in net],
                                     notes=[f"n={int(f(r['customers'])):,}, avg ${f(r['avg_monthly_charges']):.0f}/mo" for r in net],
                                     ylabel="churn rate %", vmax=50)),
        ("addon_churn_effect", S.grouped_vbar("Churn with vs without each add-on (internet customers, %)",
                                              [r["addon"].replace("Streaming ", "Stream. ").replace("Device protection", "Device prot.") for r in add],
                                              [("without add-on", [f(r["churn_rate_without_pct"]) for r in add]),
                                               ("with add-on", [f(r["churn_rate_with_pct"]) for r in add])], "{:.1f}",
                                              "security and tech support cut churn by ~27 points; streaming barely matters",
                                              ylabel="churn rate %")),
        ("churn_by_addon_count", S.vbar("Churn rate by number of add-ons (internet customers, %)", [r["addon_count"] for r in acnt],
                                        [f(r["churn_rate_pct"]) for r in acnt], "{:.1f}%",
                                        "0 add-ons: half churn; all 6: about 1 in 20 (more add-ons also means longer tenure)",
                                        color=[heat(f(r["churn_rate_pct"]), avg) for r in acnt],
                                        notes=[f"n={int(f(r['customers'])):,}" for r in acnt], ylabel="churn rate %", vmax=60)),
        ("churn_drivers", S.dbar("Single-factor churn drivers: churn if true minus if false (pts)", [r["factor"] for r in drv],
                                 [f(r["churn_diff_pp"]) for r in drv], "{:+.1f}",
                                 "one factor at a time, not a model (factors overlap, e.g. fiber and month-to-month)",
                                 h=520, xlabel="percentage points (red = more churn, blue = less)", pos_color=RED, neg_color=BLUE)),
        ("revenue_at_risk_segments", S.hbar("Monthly revenue lost by contract x internet ($k)",
                                            [f"{r['contract']} / {r['internet_service']}" for r in mat],
                                            [f(r["mrr_lost"]) / 1e3 for r in mat], "${:,.1f}k",
                                            f"${f(k['mrr_lost']) / 1e3:,.1f}k of ${f(k['mrr_total']) / 1e3:,.1f}k MRR left with churners "
                                            f"(${f(k['annualised_revenue_lost']) / 1e6:.2f}M a year)",
                                            color=[heat(f(r["churn_rate_pct"]), avg) for r in mat],
                                            notes=[f"churn {f(r['churn_rate_pct']):.1f}%, n={int(f(r['customers'])):,}" for r in mat], vmax=120)),
        ("churn_by_demographics", S.grouped_vbar("Churn rate by demographics (%)", dims,
                                                 [("No", [f(dem[(d, 'No')]["churn_rate_pct"]) for d in dims]),
                                                  ("Yes", [f(dem[(d, 'Yes')]["churn_rate_pct"]) for d in dims])], "{:.1f}",
                                                 f"gender makes no difference (female {f(dem[('Gender', 'Female')]['churn_rate_pct']):.1f}% vs "
                                                 f"male {f(dem[('Gender', 'Male')]['churn_rate_pct']):.1f}%)", ylabel="churn rate %")),
    ], k, rev


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    ps, k, rev = panels(tables)
    for name, p in ps:
        S.save(p, out / f"{name}.svg")
    cards = [("Customers", f"{int(f(k['customers'])):,}"), ("Churned", f"{int(f(k['churned_customers'])):,}"),
             ("Churn rate", f"{f(k['churn_rate_pct']):.1f}%"), ("MRR", f"${f(k['mrr_total']) / 1e3:,.0f}k"),
             ("MRR lost (at risk)", f"${f(k['mrr_lost']) / 1e3:,.1f}k ({f(k['mrr_lost_pct']):.1f}%)"),
             ("Annualised loss", f"${f(k['annualised_revenue_lost']) / 1e6:.2f}M"),
             ("Median tenure churned / kept", f"{f(k['median_tenure_churned']):.0f} / {f(k['median_tenure_retained']):.0f} m")]
    order = ["churn_by_contract", "churn_by_tenure_band", "churn_by_internet", "churn_by_payment",
             "addon_churn_effect", "revenue_at_risk_segments"]
    dash = [dict(ps)[n] for n in order]
    S.dashboard(out / "dashboard.svg", "Telco customer churn: who leaves, when, and how much revenue goes with them",
                f"Rendered from results/tables (SQL on DuckDB). IBM Telco sample, {int(f(k['customers'])):,} customers, "
                f"one snapshot; churn = left within the last month; red bars = above the {f(k['churn_rate_pct']):.1f}% average.",
                cards, dash, cols=2)
    print("charts ->", out, sorted(p.name for p in out.glob("*.svg")))


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/images")
