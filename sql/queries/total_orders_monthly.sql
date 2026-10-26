-- Zapytanie podsumowuje liczbę zamówień w sklepie internetowym w 
-- 12 analizowanych miesiącach

WITH orders_yearmonth AS (
SELECT
	id_order,
	STRFTIME(DATE_TRUNC('month',date_add),'%Y-%m') AS date_add_yearmonth
FROM 
	ps_orders
WHERE
	date_add >= '2025-10-01'
	AND date_add < '2026-10-01'  -- interesuje nas 12 miesiecy
),

orders_yearmonth_aggregated AS (
SELECT
	--ROW_NUMBER() OVER ORDER BY (date_add_yearmonth) AS lp,
	date_add_yearmonth,
	COUNT(date_add_yearmonth) AS order_totals
FROM
	orders_yearmonth
GROUP BY
	date_add_yearmonth
ORDER BY
	date_add_yearmonth
)

SELECT
	ROW_NUMBER() OVER (ORDER BY date_add_yearmonth) AS lp,
	date_add_yearmonth,
	order_totals
FROM
	orders_yearmonth_aggregated;