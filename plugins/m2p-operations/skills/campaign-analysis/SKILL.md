---
name: campaign-analysis
description: Pull a standardized campaign-level daily report by campaign_id. Shows CPC, cost (OOB highlighted), clicks, 1d/7d ACOS, budget, and TOS/ROS/PP placement multipliers. Supports both SP and SB campaigns.
---

# Campaign Analysis Report

Use this skill whenever the user asks to "investigate a campaign", "campaign analysis", or "campaign report" for a given campaign ID. Produces a standardized daily table.

## Inputs

- `campaign_id` — required. The campaign ID (e.g. `233983799751608`). Treated as a string in BQ.
- `lookback_days` — optional, default `30`.

## Step 1: Detect campaign type (SP or SB)

Run this query first to determine the ad type:

```sql
SELECT DISTINCT bid_type
FROM `move2play-cloud.sponsored_brands_products_bids.audience_placement_bid_history`
WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
  AND bid_type IN ('sp_placement', 'sb_placement')
LIMIT 1;
```

- If `sp_placement` → SP campaign. Use SP tables and show **TOS / ROS / PP** columns.
- If `sb_placement` → SB campaign. Use SB tables and show **TOS / ROS** columns only (no PP for SB).
- If no rows, fall back: check `sp_campaigns` or `sb_campaigns` for the campaign_id.

## Output format

**Header (above the table):**
- Campaign name
- Campaign ID
- Type: SP or SB
- Current daily budget

**Table columns:**

For **SP** campaigns:
`Date | CPC | Cost | Budget | Clicks | 1d ACOS | 7d ACOS | TOS | ROS | PP`

For **SB** campaigns:
`Date | CPC | Cost | Budget | Clicks | 1d ACOS | 7d ACOS | TOS | ROS`

**Column definitions:**
- `CPC` = total cost / total clicks for that day
- `Cost` = total daily spend. Append **OOB** if cost >= budget for that day.
- `Budget` = daily budget from the performance table's `campaign_budget_amount`
- `Clicks` = total daily clicks
- `1d ACOS` = cost / sales for that single day. Null → show as `—`.
- `7d ACOS` = trailing 7-day rolling `SUM(cost) / SUM(sales)`.
- `TOS` = Top of Search placement bid adjustment % (from `audience_placement_bid_history`)
- `ROS` = Rest of Search (SP) or Other Placements (SB) bid adjustment %
- `PP` = Product Pages bid adjustment % (SP only)

## Data sources

All tables live in project `move2play-cloud`, dataset `sponsored_brands_products_bids`.

### SP campaigns

| Purpose | Table | Key columns |
|---|---|---|
| Daily performance by placement | `sp_campaigns` | `campaign_id`, `date`, `placement_classification`, `cost`, `clicks`, `sales_7d`, `campaign_budget_amount`, `top_of_search_impression_share` |
| Campaign metadata | `sp_campaign_list` | `campaign_id`, `campaign_name`, `campaign_budget` |
| Placement multiplier history | `audience_placement_bid_history` | `campaign_id`, `bid_type='sp_placement'`, `bid_type_id` IN (`PLACEMENT_TOP`, `PLACEMENT_REST_OF_SEARCH`, `PLACEMENT_PRODUCT_PAGE`) |

SP placement classifications in `sp_campaigns`: `Top of Search on-Amazon`, `Rest of Search`, `Detail Page on-Amazon`, `Other on-Amazon`, `Off Amazon`.

**Important:** `sp_campaigns` stores sales with attribution windows (`sales_1d`, `sales_7d`, `sales_30d`). Use `sales_7d` for ACOS calculations (standard Amazon 7-day attribution).

### SB campaigns

| Purpose | Table | Key columns |
|---|---|---|
| Daily performance (campaign totals) | `sb_campaigns` | `campaign_id`, `date`, `cost`, `clicks`, `sales`, `top_of_search_impression_share` |
| Daily performance by placement + budget | `sb_placement` | `campaign_id`, `date`, `placement_classification`, `cost`, `clicks`, `sales`, `campaign_budget_amount` |
| Campaign metadata | `sb_campaign_list` | `campaign_id`, `campaign_name`, `campaign_budget` |
| Placement multiplier history | `audience_placement_bid_history` | `campaign_id`, `bid_type='sb_placement'`, `bid_type_id` IN (`TOP_OF_SEARCH`, `OTHER`) |

SB placement classifications in `sb_placement`: `Top of Search on-Amazon`, `Other on-Amazon`.

## Query templates

### SP campaign query

```sql
WITH camp AS (
  SELECT
    date AS d,
    SUM(cost) AS cost,
    SUM(clicks) AS clicks,
    SUM(sales_7d) AS sales,
    MAX(campaign_budget_amount) AS budget
  FROM `move2play-cloud.sponsored_brands_products_bids.sp_campaigns`
  WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
    AND date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  GROUP BY date
),
adj_daily AS (
  SELECT
    DATE(created_at) AS d,
    bid_type_id,
    ARRAY_AGG(CAST(bid AS FLOAT64) ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS adjustment
  FROM `move2play-cloud.sponsored_brands_products_bids.audience_placement_bid_history`
  WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
    AND bid_type = 'sp_placement'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  GROUP BY DATE(created_at), bid_type_id
),
adj_pivot AS (
  SELECT d,
    MAX(CASE WHEN bid_type_id = 'PLACEMENT_TOP' THEN adjustment END) AS tos_adj,
    MAX(CASE WHEN bid_type_id = 'PLACEMENT_REST_OF_SEARCH' THEN adjustment END) AS ros_adj,
    MAX(CASE WHEN bid_type_id = 'PLACEMENT_PRODUCT_PAGE' THEN adjustment END) AS pp_adj
  FROM adj_daily
  GROUP BY d
)
SELECT
  c.d,
  ROUND(SAFE_DIVIDE(c.cost, c.clicks), 2) AS cpc,
  ROUND(c.cost, 2) AS cost,
  ROUND(c.budget, 0) AS budget,
  CASE WHEN c.cost >= c.budget THEN 'OOB' ELSE '' END AS oob,
  c.clicks,
  ROUND(SAFE_DIVIDE(c.cost, c.sales), 4) AS acos_1d,
  ROUND(
    SUM(c.cost) OVER (ORDER BY c.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) /
    NULLIF(SUM(c.sales) OVER (ORDER BY c.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0),
    4
  ) AS acos_7d,
  a.tos_adj,
  a.ros_adj,
  a.pp_adj
FROM camp c
LEFT JOIN adj_pivot a USING (d)
WHERE c.d <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)
ORDER BY c.d DESC
LIMIT {LOOKBACK_DAYS};
```

### SB campaign query

```sql
WITH camp AS (
  SELECT
    c.date AS d,
    c.cost,
    c.clicks,
    c.sales,
    MAX(p.campaign_budget_amount) AS budget
  FROM `move2play-cloud.sponsored_brands_products_bids.sb_campaigns` c
  LEFT JOIN (
    SELECT date, MAX(campaign_budget_amount) AS campaign_budget_amount
    FROM `move2play-cloud.sponsored_brands_products_bids.sb_placement`
    WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
      AND date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
    GROUP BY date
  ) p ON c.date = p.date
  WHERE CAST(c.campaign_id AS STRING) = '{CAMPAIGN_ID}'
    AND c.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  GROUP BY c.date, c.cost, c.clicks, c.sales
),
adj_daily AS (
  SELECT
    DATE(created_at) AS d,
    bid_type_id,
    ARRAY_AGG(CAST(bid AS FLOAT64) ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS adjustment
  FROM `move2play-cloud.sponsored_brands_products_bids.audience_placement_bid_history`
  WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
    AND bid_type = 'sb_placement'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL {LOOKBACK_DAYS}+2 DAY)
  GROUP BY DATE(created_at), bid_type_id
),
adj_pivot AS (
  SELECT d,
    MAX(CASE WHEN bid_type_id = 'TOP_OF_SEARCH' THEN adjustment END) AS tos_adj,
    MAX(CASE WHEN bid_type_id = 'OTHER' THEN adjustment END) AS ros_adj
  FROM adj_daily
  GROUP BY d
)
SELECT
  c.d,
  ROUND(SAFE_DIVIDE(c.cost, c.clicks), 2) AS cpc,
  ROUND(c.cost, 2) AS cost,
  ROUND(c.budget, 0) AS budget,
  CASE WHEN c.cost >= c.budget THEN 'OOB' ELSE '' END AS oob,
  c.clicks,
  ROUND(SAFE_DIVIDE(c.cost, c.sales), 4) AS acos_1d,
  ROUND(
    SUM(c.cost) OVER (ORDER BY c.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) /
    NULLIF(SUM(c.sales) OVER (ORDER BY c.d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0),
    4
  ) AS acos_7d,
  a.tos_adj,
  a.ros_adj
FROM camp c
LEFT JOIN adj_pivot a USING (d)
WHERE c.d <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)
ORDER BY c.d DESC
LIMIT {LOOKBACK_DAYS};
```

### Campaign name lookup

```sql
-- Try SP first
SELECT campaign_name, campaign_budget, campaign_budget_type
FROM `move2play-cloud.sponsored_brands_products_bids.sp_campaign_list`
WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
LIMIT 1;

-- If empty, try SB
SELECT campaign_name, campaign_budget, campaign_budget_type
FROM `move2play-cloud.sponsored_brands_products_bids.sb_campaign_list`
WHERE CAST(campaign_id AS STRING) = '{CAMPAIGN_ID}'
LIMIT 1;
```

## Rendering rules

- Render as a Markdown table.
- Format currency as `$X.XX` and ACOS as percentages with one decimal (e.g. `33.5%`).
- Placement adjustments as whole percentages (e.g. `6%`, `0%`).
- **OOB**: Append `**OOB**` (bold) to the Cost cell when cost >= budget.
- **Change arrows**: When `Budget`, `TOS`, `ROS`, or `PP` changes from the prior day, show as `$250⇒$200` or `0%⇒2%`. Compare against the chronologically prior day (rows are sorted DESC, so prior day = next row down).
- Null `1d ACOS` → `—`.
- Sort by most recent date first.
- **Exclude today and yesterday** — data is incomplete.
- Default lookback: 30 days.

## Post-table observations

After the table, include a brief "Key observations" section noting:
- OOB frequency (how many days hitting budget)
- Volume trend (clicks increasing/decreasing)
- 7d ACOS trend vs any known target
- Budget changes and their impact on volume
- Notable placement adjustment changes

## Notes / gotchas

- `campaign_id` is stored as STRING in some tables and INT64 in others. Always cast when filtering.
- For SP, use `sales_7d` (not `sales_1d`) for ACOS — this matches Amazon's standard 7-day attribution.
- For SB, the `sales` column in `sb_campaigns` already uses 7-day attribution.
- SB campaigns only have TOS and "Other Placements" (no PP). Never show a PP column for SB.
- The `audience_placement_bid_history` table stores adjustments as percentages (e.g. `6.0` = 6% boost, `0.0` = no boost).
- Budget comes from the performance tables (`campaign_budget_amount`) which capture the historical daily value, not from `*_campaign_list` which only shows current budget.
