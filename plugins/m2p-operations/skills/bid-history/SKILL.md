---
name: bid-history
description: Pull a standardized bid history report for a Sponsored Products keyword by keyword_id. Shows daily bid-to-use, expected vs actual CPC, cost, clicks, target ACOS, and 1d/7d rolling ACOS with change tracking arrows.
---

# Bid History Report

Use this skill whenever the user asks for "bid history" for a keyword / element ID (Sponsored Products). Produces a standardized table so reports look the same across runs.

## Inputs

- `keyword_id` — required. The SP keyword ID (e.g. `436983429568513`). Treated as a string in BQ.
- `lookback_days` — optional, default `30`.

## Output format

**Header (above the table):**
- Campaign name
- Ad Group name
- Keyword name + ID

**Table columns (in order):**
`Date | Bid to Use | Expected CPC | Actual CPC | Cost | Clicks | Target ACOS | 1d ACOS | 7d ACOS`

**Rules:**
- Sort by most recent date first.
- **Exclude today and yesterday** — data is incomplete.
- Default lookback: 30 days.
- `Expected CPC = bid_to_use / placement_factor`
- `Actual CPC` from `sp_kw_targeting` daily totals: `cost / clicks`.
- `1d ACOS = cost / sales` for that single day. Null → show as `—`.
- `7d ACOS` = trailing 7-day rolling `SUM(cost) / SUM(sales)`.
- When `Bid to Use` or `Target ACOS` changes from the prior day, show as `$0.53⇒$0.65` / `35%⇒37%` in the same cell. Otherwise show the current value only.
- Flag the last-row trend if 7d ACOS crosses target.

## Data sources

All tables live in project `move2play-cloud`, dataset `sponsored_brands_products_bids`.

| Purpose | Table | Join key |
|---|---|---|
| Keyword metadata (campaign/ad group/keyword text/placement factor) | `SP_Dynamic_Data_1_Live` | `CAST(keyword_id AS STRING)` |
| Daily bid changes (hourly granularity, pick last per day) | `sp_kw_bid_history` | `keyword_id` (STRING) |
| Daily cost/clicks/sales — keyword targets | `sp_kw_targeting` | `CAST(keyword_id AS STRING)` |
| Daily cost/clicks/sales — Auto-campaign targets (loose-match, close-match, substitutes, complements) | `sp_adgroup_targeting` | `target_id` (STRING) = keyword_id |

Auto-campaign synthetic keyword_ids do NOT appear in `sp_kw_targeting` — they appear in `sp_adgroup_targeting` keyed by `target_id`. The query must UNION ALL both sources so the report works for both manual keywords and Auto targets.

Note: `sp_kw_bid_history.sc_bid` is the **base bid** (the "bid to use"). `sp_kw_bid_history.bid` is the hourly day-parted bid — do not use that for the daily snapshot. Take the last `sc_bid` of each day.

`sp_kw_bid_history.placement_adjustment_to_use` holds the historical placement factor at the time the bid was set — use this (not the current value from `SP_Dynamic_Data_1_Live`) so Expected CPC is correct for each historical day.

## Query template

Substitute `{KEYWORD_ID}` and `{LOOKBACK_DAYS}` (default 30). Lookback is padded by 2 days to ensure we have enough bid-history rows before dropping today/yesterday.

```sql
WITH bid_daily AS (
  SELECT
    DATE(created_at) AS d,
    ARRAY_AGG(sc_bid ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS bid_to_use,
    ARRAY_AGG(target_acos ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS target_acos,
    ARRAY_AGG(placement_adjustment_to_use ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS placement_factor
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_kw_bid_history`
  WHERE keyword_id = '{KEYWORD_ID}'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  GROUP BY d
),
perf_union AS (
  SELECT date AS d, cost, clicks, sales
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_kw_targeting`
  WHERE CAST(keyword_id AS STRING) = '{KEYWORD_ID}'
    AND date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  UNION ALL
  SELECT date AS d, cost, clicks, sales_7d AS sales
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_adgroup_targeting`
  WHERE target_id = '{KEYWORD_ID}'
    AND date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
),
perf_daily AS (
  SELECT d, SUM(cost) AS cost, SUM(clicks) AS clicks, SUM(sales) AS sales
  FROM perf_union
  GROUP BY d
)
SELECT
  b.d,
  b.bid_to_use,
  b.placement_factor,
  ROUND(b.bid_to_use / NULLIF(b.placement_factor, 0), 3) AS expected_cpc,
  ROUND(SAFE_DIVIDE(p.cost, p.clicks), 3)                AS actual_cpc,
  ROUND(p.cost, 2)                                        AS cost,
  p.clicks,
  ROUND(b.target_acos, 4)                                 AS target_acos,
  ROUND(SAFE_DIVIDE(p.cost, p.sales), 4)                  AS acos_1d,
  ROUND(
    SUM(p.cost)  OVER (ORDER BY b.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) /
    NULLIF(SUM(p.sales) OVER (ORDER BY b.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0),
    4
  ) AS acos_7d
FROM bid_daily b
LEFT JOIN perf_daily p USING (d)
WHERE b.d <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)
ORDER BY b.d DESC
LIMIT {LOOKBACK_DAYS};
```

For the header lookup:

```sql
SELECT campaign_name, ad_group_name, keyword, match_type, keyword_id, placement_factor
FROM `move2play-cloud.sponsored_brands_products_bids.SP_Dynamic_Data_1_Live`
WHERE CAST(keyword_id AS STRING) = '{KEYWORD_ID}'
LIMIT 1;
```

## Rendering rules

- Render as a Markdown table.
- Format currency as `$X.XX` and ACOS as percentages with one decimal (e.g. `33.5%`).
- For change tracking, compare the current row's `bid_to_use` / `target_acos` against the row of the **prior day** (not the prior row in the output — rows are sorted DESC, so look at `d - 1`).
- Null `1d ACOS` → `—`.
- After the table, add a one-line observation if 7d ACOS has trended above or below target in the most recent rows.

## Notes / gotchas

- `keyword_id` is stored as STRING in `sp_kw_bid_history` and `SP_Dynamic_Data_1_Live`, and as INT64 in `sp_kw_targeting`. Always cast when joining or filtering.
- `sp_kw_targeting.sales` is already attributed with Amazon's 7-day attribution window — use it directly for ACOS calculations.
- Do not round CBM/units/raw values elsewhere, but rounding currency/percentages for display is fine in this report.
