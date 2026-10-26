-- Przykłady dla DuckDB
-- (1) AOV (opłacone, bez anulacji)
SELECT date_trunc('month', CAST(date_add AS TIMESTAMP)) AS month,
       COUNT(*) AS orders_count,
       ROUND(AVG(total_paid_tax_incl),2) AS aov_gross
FROM ps_orders WHERE id_order_state IN (2,3,4,6)
GROUP BY 1 ORDER BY 1;

-- (2) Funnel na poziomie sesji, z botami wykluczonymi
SELECT e.event_name, COUNT(DISTINCT e.session_id) AS sessions
FROM ga4_events e JOIN ga4_sessions s USING(session_id)
WHERE s.is_bot = 0
  AND e.event_name IN ('session_start','view_item','add_to_cart','begin_checkout','purchase')
GROUP BY 1 ORDER BY 1;

-- (3) Brakujące eventy purchase na bazie reference
SELECT o.id_order, o.reference, o.date_add, o.total_paid_tax_incl
FROM ps_orders o LEFT JOIN ga4_events e ON e.transaction_id = o.reference AND e.event_name='purchase'
WHERE e.event_id IS NULL ORDER BY o.id_order;

-- (4) Zduplikowany purchase w GA4
SELECT transaction_id, COUNT(*) AS purchases
FROM ga4_events WHERE event_name='purchase' AND transaction_id IS NOT NULL
GROUP BY 1 HAVING COUNT(*) > 1 ORDER BY purchases DESC;

-- (5) Stany magazynowe z ruchów
SELECT a.id_product_attribute,
       a.quantity AS reported_quantity,
       SUM(m.quantity_delta) AS derived_quantity
FROM ps_stock_available a JOIN inventory_movements m USING(id_product_attribute)
GROUP BY 1,2 HAVING a.quantity != SUM(m.quantity_delta);
