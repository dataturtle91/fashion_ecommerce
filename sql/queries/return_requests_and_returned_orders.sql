-- Zamówienia zwrócone według miesiąca ich utworzenia, zgłoszenia zwrotów w danym miesiącu, zgłoszenia zaakceptowane według daty aktualizacji zgłoszenia
WITH return_requests_add AS (

SELECT
    STRFTIME(date_trunc('month', date_add),'%Y-%m') AS year_month,
    COUNT(id_order) AS return_requests_add
FROM 
	ps_order_return 
GROUP BY
	STRFTIME(date_trunc('month', date_add),'%Y-%m')
ORDER BY
	 STRFTIME(date_trunc('month', date_add),'%Y-%m')
	 
),

return_requests_accepted AS (
SELECT
    STRFTIME(date_trunc('month', date_upd),'%Y-%m') AS year_month,
    COUNT(id_order) AS return_requests_accepted
FROM 
	ps_order_return
WHERE
	state = 'accepted'
GROUP BY
	STRFTIME(date_trunc('month', date_upd),'%Y-%m')
ORDER BY
	 STRFTIME(date_trunc('month', date_upd),'%Y-%m')	 
),

return_orders AS (
SELECT
    STRFTIME(date_trunc('month', date_add),'%Y-%m') AS year_month,
    COUNT(id_order) AS returned_orders			
FROM 
	ps_orders o
WHERE 
	o.id_order_state = 6
GROUP BY
	STRFTIME(date_trunc('month', date_add),'%Y-%m')
ORDER BY
	 STRFTIME(date_trunc('month', date_add),'%Y-%m')
),
months AS (
    SELECT year_month FROM return_orders
    UNION
    SELECT year_month FROM return_requests_add
    UNION
    SELECT year_month FROM return_requests_accepted
)
SELECT
    m.year_month,
    COALESCE(ro.returned_orders, 0) AS returned_orders,
    COALESCE(rrad.return_requests_add, 0) AS return_requests_add,
    COALESCE(rrac.return_requests_accepted, 0) AS accepted_requests_by_update_month
FROM months m
LEFT JOIN return_orders ro ON m.year_month = ro.year_month
LEFT JOIN return_requests_add rrad ON m.year_month = rrad.year_month
LEFT JOIN return_requests_accepted rrac ON m.year_month = rrac.year_month
ORDER BY 
	m.year_month;