CREATE OR REPLACE PROCEDURE `move2play-cloud.sponsored_brands_products_bids.sp_declining_spend_routine`()
BEGIN

  CREATE OR REPLACE TABLE `move2play-cloud.sponsored_brands_products_bids.sp_declining_spend` AS

  WITH
  bid_daily AS (
    SELECT keyword_id, DATE(created_at) AS d,
      ARRAY_AGG(sc_bid ORDER BY created_at DESC LIMIT 1)[OFFSET(0)] AS bid
    FROM `move2play-cloud.sponsored_brands_products_bids.sp_kw_bid_history`
    WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 25 DAY)
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
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
    UNION ALL
    SELECT target_id AS kw, date AS d, cost, clicks, impressions, sales_7d AS sales
    FROM `move2play-cloud.sponsored_brands_products_bids.sp_adgroup_targeting`
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
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
      AND bc.change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
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
      (w.pre_cost_7d / 7) - (w.post_cost_w / NULLIF(LEAST(7, w.post_days_avail),0)) AS lost_dollars_per_day,
      SAFE_DIVIDE(w.pre_cost_7d, w.pre_clicks_7d)  AS pre_cpc,
      SAFE_DIVIDE(w.post_cost_w, w.post_clicks_w)  AS post_cpc
    FROM windows w
    WHERE w.bid_pct <= -0.05
      AND w.pre_sales_7d > 0
  )

  SELECT
    s.change_date,
    s.keyword_id                                            AS element_id,
    e.campaign_name,
    e.ad_group_name,
    COALESCE(e.keyword_text, e.target_name)                 AS keyword,
    e.match_type,
    s.prev_bid,
    s.new_bid,
    s.bid_pct                                               AS bid_chg_pct,
    s.pre_acos,
    s.post_acos,
    s.pre_cost_per_day,
    s.post_cost_per_day,
    s.lost_dollars_per_day,
    s.pre_cpc,
    s.post_cpc,
    s.post_days,
    s.cost_chg_pct,
    s.clicks_chg_pct
  FROM scored s
  INNER JOIN `move2play-cloud.sponsored_brands_products_bids.sp_enabled_kw_and_targets` e
    ON COALESCE(e.keyword_id, e.target_id) = s.keyword_id
  WHERE UPPER(e.keyword_status)    = 'ENABLED'
    AND UPPER(e.campaign_status)   = 'ENABLED'
    AND UPPER(e.ad_group_status)   = 'ENABLED'
    AND s.pre_acos                 < 0.45
    AND s.impr_chg_pct             <= -0.5
    AND s.impr_chg_pct             < s.bid_pct * 2
    AND s.pre_cost_per_day         > 5
  ORDER BY s.lost_dollars_per_day DESC;

END;
