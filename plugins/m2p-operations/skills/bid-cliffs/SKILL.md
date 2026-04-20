---
name: bid-cliffs
description: Detect Sponsored Products bid decreases that caused disproportionate campaign performance collapse — the "auction cliff" pattern where a small bid cut knocks a keyword below the clearing price and spend/clicks drop far more than the bid did. Flags revert candidates with pre/post ACOS, CPC, and spend comparisons.
---

# Bid Cliff Detector

Use this skill when the user asks to detect bid cuts that caused campaigns to stop performing (also called "bid cliffs" or "auction cliffs"). Produces a standardized table of candidate keywords that likely need a bid revert.

## When to trigger

- "Find bid cliffs" / "detect bid cliffs"
- "Which keywords stopped performing after a bid cut?"
- "Show me bid decreases that tanked a campaign"
- User mentions a recurring failure mode where small bid cuts (5–9%) cause 70–100% spend collapse

## Inputs

- `lookback_days` — optional, default `14`. Window for bid changes to analyze.
- `min_pre_clicks_per_day` — optional, default `5` (i.e. 35 clicks over 7 days). Filter out low-baseline noise.
- `max_pre_acos` — optional, default `0.45`. Only flag keywords that were profitable enough to be worth keeping.

## Output format

**Table columns (in order):**
`Date | Element ID | Campaign | Ad Group | Keyword | Match | Bid | Bid Δ | Pre ACOS → Post ACOS | Pre $/d → Post $/d | Pre CPC → Post CPC | Cost Δ | Clicks Δ`

**Rules:**
- Show top 10 cliffs sorted by gap severity (biggest disproportionate drop first).
- Post-window columns (ACOS, $/d, CPC) annotated with `(Nd)` where N is days in post window (up to 7) when <7 full days are available.
- Pre ACOS → Post ACOS as single combined cell; same for Pre $/d → Post $/d and Pre CPC → Post CPC.
- Cost Δ and Clicks Δ are normalized to per-day rates so the comparison is fair when post window <7 days.
- Only include keywords/targets that are currently **ENABLED** at campaign, ad_group, and keyword level.
- Exclude change dates newer than `today - 3 days` (need enough post data to compute the signal).
- Exclude the last 2 days from post window (data incomplete).
- Skip keywords where `pre_sales < $1` or `pre_clicks < min_pre_clicks_per_day × 7`.

## Detection thresholds

- **Bid cut**: `bid_pct ≤ -5%`
- **Baseline**: pre-window ≥ 5 clicks/day (35/week), pre-sales > 0
- **Pre-ACOS filter**: `< 45%` (excludes keywords that deserved a cut)
- **Cliff criteria** (all three):
  1. Impressions dropped ≥ 50% per day post-change
  2. Impression drop is at least **2× the bid drop** (the disproportionality test)
  3. Bid cut ≥ 5%

## Data sources (project `move2play-cloud`, dataset `sponsored_brands_products_bids`)

| Purpose | Table | Key |
|---|---|---|
| Daily bids | `sp_kw_bid_history` | `keyword_id` (STRING). Use last `sc_bid` per `DATE(created_at)` |
| Keyword-target perf | `sp_kw_targeting` | `CAST(keyword_id AS STRING)` |
| Auto-target perf (loose/close-match, substitutes, complements) | `sp_adgroup_targeting` | `target_id` (STRING) — sales column is `sales_7d` |
| Enabled status + names | `sp_enabled_kw_and_targets` | `COALESCE(keyword_id, target_id)` |

UNION ALL the two perf tables so Auto-campaign targets and keyword targets both resolve.

## Decision framework for revert candidates

After producing the table, add a summary categorizing the 10 rows:

| Post ACOS signal | Recommendation |
|---|---|
| Post ACOS ≤ pre, or improved | **Revert** — cut erased profitable volume |
| Post ACOS moderately higher but still workable (< target × 1.5) | **Revert with partial bid** — restore some volume |
| Post ACOS severely blown out (> 2× pre) | **Leave cut** — remaining traffic unprofitable at any bid |
| Post has no sales (—) and only 2–3 post days | Too early to judge — flag for re-check |

CPC direction is a secondary signal:
- CPC rose post-cut → got pushed to worse placements (bad sign)
- CPC flat/fell → lost auctions cleanly, proportional to bid band

## Query template

Substitute `{LOOKBACK_DAYS}` (default 14), `{MIN_PRE_CLICKS_7D}` (default 35), `{MAX_PRE_ACOS}` (default 0.45).

```sql
WITH bid_daily AS (
  SELECT keyword_id, DATE(created_at) AS d,
    ARRAY_AGG(sc_bid ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS bid
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_kw_bid_history`
  WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+11 DAY)
  GROUP BY keyword_id, d
),
bid_changes AS (
  SELECT keyword_id, d AS change_date, bid AS new_bid,
    LAG(bid) OVER (PARTITION BY keyword_id ORDER BY d) AS prev_bid
  FROM bid_daily
),
perf AS (
  SELECT CAST(keyword_id AS STRING) AS kw, date AS d, cost, clicks, impressions, sales
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_kw_targeting`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+16 DAY)
  UNION ALL
  SELECT target_id AS kw, date AS d, cost, clicks, impressions, sales_7d AS sales
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_adgroup_targeting`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+16 DAY)
),
perf_daily AS (
  SELECT kw, d, SUM(cost) AS cost, SUM(clicks) AS clicks, SUM(impressions) AS impr, SUM(sales) AS sales
  FROM perf GROUP BY kw, d
),
windows AS (
  SELECT bc.*,
    SAFE_DIVIDE(bc.new_bid - bc.prev_bid, bc.prev_bid) AS bid_pct,
    DATE_DIFF(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY), bc.change_date, DAY) + 1 AS post_days_avail,
    (SELECT SUM(impr)   FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN DATE_SUB(bc.change_date,INTERVAL 7 DAY) AND DATE_SUB(bc.change_date,INTERVAL 1 DAY)) AS pre_impr_7d,
    (SELECT SUM(clicks) FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN DATE_SUB(bc.change_date,INTERVAL 7 DAY) AND DATE_SUB(bc.change_date,INTERVAL 1 DAY)) AS pre_clicks_7d,
    (SELECT SUM(cost)   FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN DATE_SUB(bc.change_date,INTERVAL 7 DAY) AND DATE_SUB(bc.change_date,INTERVAL 1 DAY)) AS pre_cost_7d,
    (SELECT SUM(sales)  FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN DATE_SUB(bc.change_date,INTERVAL 7 DAY) AND DATE_SUB(bc.change_date,INTERVAL 1 DAY)) AS pre_sales_7d,
    (SELECT SUM(impr)   FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN bc.change_date AND LEAST(DATE_ADD(bc.change_date,INTERVAL 6 DAY), DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 2 DAY))) AS post_impr_w,
    (SELECT SUM(clicks) FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN bc.change_date AND LEAST(DATE_ADD(bc.change_date,INTERVAL 6 DAY), DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 2 DAY))) AS post_clicks_w,
    (SELECT SUM(cost)   FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN bc.change_date AND LEAST(DATE_ADD(bc.change_date,INTERVAL 6 DAY), DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 2 DAY))) AS post_cost_w,
    (SELECT SUM(sales)  FROM perf_daily p WHERE p.kw=bc.keyword_id AND p.d BETWEEN bc.change_date AND LEAST(DATE_ADD(bc.change_date,INTERVAL 6 DAY), DATE_SUB(CURRENT_DATE('America/Los_Angeles'),INTERVAL 2 DAY))) AS post_sales_w
  FROM bid_changes bc
  WHERE bc.prev_bid IS NOT NULL AND bc.new_bid < bc.prev_bid
    AND bc.change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS} DAY)
    AND bc.change_date <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
),
scored AS (
  SELECT w.*,
    LEAST(7, w.post_days_avail) AS post_days,
    SAFE_DIVIDE(w.post_cost_w / NULLIF(LEAST(7, w.post_days_avail),0), w.pre_cost_7d / 7) - 1 AS cost_chg_pct,
    SAFE_DIVIDE(w.post_clicks_w / NULLIF(LEAST(7, w.post_days_avail),0), w.pre_clicks_7d / 7) - 1 AS clicks_chg_pct,
    SAFE_DIVIDE(w.post_impr_w / NULLIF(LEAST(7, w.post_days_avail),0), w.pre_impr_7d / 7) - 1 AS impr_chg_pct,
    SAFE_DIVIDE(w.pre_cost_7d, w.pre_sales_7d) AS pre_acos,
    SAFE_DIVIDE(w.post_cost_w, w.post_sales_w) AS post_acos,
    w.pre_cost_7d / 7 AS pre_cost_per_day,
    w.post_cost_w / NULLIF(LEAST(7, w.post_days_avail),0) AS post_cost_per_day,
    SAFE_DIVIDE(w.pre_cost_7d, w.pre_clicks_7d)  AS pre_cpc,
    SAFE_DIVIDE(w.post_cost_w, w.post_clicks_w)  AS post_cpc
  FROM windows w
  WHERE w.bid_pct <= -0.05
    AND w.pre_sales_7d > 0
    AND w.pre_clicks_7d >= {MIN_PRE_CLICKS_7D}
)
SELECT
  s.change_date, s.keyword_id AS element_id,
  e.campaign_name, e.ad_group_name,
  COALESCE(e.keyword_text, e.target_name) AS kw_text,
  e.match_type,
  s.prev_bid, s.new_bid,
  ROUND(s.bid_pct*100,1) AS bid_chg_pct,
  ROUND(s.pre_acos*100,1)  AS pre_acos_pct,
  ROUND(s.post_acos*100,1) AS post_acos_pct,
  ROUND(s.pre_cost_per_day,2)  AS pre_cost_per_day,
  ROUND(s.post_cost_per_day,2) AS post_cost_per_day,
  ROUND(s.pre_cpc,2)  AS pre_cpc,
  ROUND(s.post_cpc,2) AS post_cpc,
  s.post_days,
  ROUND(s.cost_chg_pct*100,1)  AS cost_chg_pct,
  ROUND(s.clicks_chg_pct*100,1) AS clicks_chg_pct
FROM scored s
INNER JOIN `move2play-cloud.sponsored_brands_products_bids.sp_enabled_kw_and_targets` e
  ON COALESCE(e.keyword_id, e.target_id) = s.keyword_id
WHERE UPPER(e.keyword_status) = 'ENABLED'
  AND UPPER(e.campaign_status) = 'ENABLED'
  AND UPPER(e.ad_group_status) = 'ENABLED'
  AND s.pre_acos < {MAX_PRE_ACOS}
  AND s.impr_chg_pct <= -0.5
  AND s.impr_chg_pct < s.bid_pct * 2
ORDER BY (s.impr_chg_pct - s.bid_pct) ASC
LIMIT 10;
```

## Rendering rules

- Markdown table.
- Bid shown as `$prev→$new`.
- ACOS as percentages with one decimal (e.g. `40.1%`); bold if post-ACOS worse than pre-ACOS.
- Currency as `$X.XX`.
- `—` for null ACOS (no sales in post window).
- After the table, produce a 4-bucket summary categorizing each row into: **Revert · Revert partial · Leave cut · Ambiguous** per the decision framework above.

## Notes / gotchas

- `keyword_id` is STRING in `sp_kw_bid_history` and `sp_enabled_kw_and_targets`, INT64 in `sp_kw_targeting`. Cast when joining.
- Auto-campaign synthetic keyword_ids appear only in `sp_adgroup_targeting` as `target_id` — must UNION ALL both perf tables.
- `sp_enabled_kw_and_targets` has either `keyword_id` OR `target_id` populated (never both) — use `COALESCE`.
- Paused/archived entities must be excluded via the ENABLED status filters, or the output will include keywords where the cliff was intentional.
- Bid pad in the `bid_daily` CTE is `{LOOKBACK_DAYS}+11` to capture the 7-day pre-window for the oldest change.
- Perf pad is `{LOOKBACK_DAYS}+16` so the pre-window lookup succeeds for changes at the edge of the window.
