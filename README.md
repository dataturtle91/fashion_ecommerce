# FashionCommerce — syntetyczny sklep odzieżowy

**Dane fikcyjne, deterministyczne (seed 48172).** Okres: 2025-10-01 – 2026-09-30 (według czasu lokalnego, bez strefy czasowej). PLN, VAT 23%, jeden sklep (`id_shop=1`). Model jest **inspirowany** realnymi encjami PrestaShop; nie stanowi eksportu ani 1:1 schematu którejkolwiek konkretnej wersji. `ga4_*` to płaskie analityczne odwzorowanie GA4, nie natywny eksport BigQuery.

## Szybki start z DuckDB

Rozpakuj archiwum, przejdź do katalogu z CSV i wykonaj:

```bash
duckdb fashion_ecommerce.duckdb < import_duckdb.sql
```
Skrypt odwołuje się do ścieżek względnych, uruchamiaj go z katalogu z plikami CSV.

Albo otwórz `fashion_ecommerce.duckdb` w kliencie DuckDB.

## Tabele i złączenia

- `ps_customer` — `id_customer` PK; `ps_address.id_customer`, `ps_cart.id_customer`, `ps_orders.id_customer` do klientów. Puste `id_customer` w koszykach/sesjach oznacza gościa anonimowego.
- `ps_category` — kategorie; `ps_product.id_category_default` do kategorii.
- `ps_product` — model odzieży; `ps_product_attribute.id_product` do modelu; `ps_product_attribute.id_product_attribute` to **wariant** (rozmiar + kolor).
- `ps_stock_available` — końcowe stany wariantów na 2026-09-30; `inventory_movements` — stan początkowy, rozchody i przyjęcia zwrotów; `inventory_stock_snapshot` — niezależne odczyty wyliczone z dziennika ruchów.
- `ps_cart` — koszyki; `ps_cart_product` — warianty w koszyku; `ps_orders.id_cart` — zamówienie danego koszyka.
- `ps_orders` — zamówienia; `ps_order_detail.id_order` — pozycje; `ps_order_history` — historia stanów; `ps_order_payment.order_reference = ps_orders.reference`; `ps_order_return` i `ps_order_return_detail` — zwroty.
- `ga4_sessions` — sesje z kanałem, kampanią i urządzeniem; `ga4_events.session_id` — zdarzenia sesji; `ga4_event_items.event_id` — warianty w zdarzeniach.
- `marketing_campaign` — słownik źródeł/kampanii; `marketing_daily_spend` — dzienny koszt; `ga4_sessions.campaign_id` dla kampanii płatnych/organicznych. Koszt jest w PLN; nie należy sumować kosztów po sesjach bez deduplikacji.

## Krytyczne reguły interpretacji

- **Identyfikator transakcji:** `ga4_events.transaction_id = ps_orders.reference`, gdy zdarzenie ma poprawny identyfikator. **Nie** łącz z `ps_orders.id_order`.
- Identyfikator koszyka: `ga4_events.id_cart = ps_cart.id_cart` (dla `add_to_cart`, `begin_checkout`, `purchase`).
- `ga4_events` zawiera także zdarzenia `session_start`, `page_view`, `view_item`, `search`.
- Ceny w `ps_product` i `ps_order_detail.unit_price_tax_excl` są **netto**; `ga4_event_items.price` to cena jednostkowa **brutto** po rabacie (dla `purchase`; w `view_item` przed rabatem). Przychód z zamówień: `ps_orders.total_paid_tax_incl` zawiera opłatę za wysyłkę. `ps_orders.total_products_tax_incl` nie obejmuje wysyłki.
- `ps_orders.total_discounts_tax_incl` to informacyjne oszczędności względem ceny katalogowej; `total_products_tax_incl` zawiera już rabat. Nie odejmuj go ponownie.
- Status 5: anulowano (nie ma płatności i nie ma rozchodu magazynowego). Status 6: oznacza zwrot **wybranej pozycji**, niekoniecznie całego zamówienia. Bezpieczne liczenie sprzedaży netto wymaga analizy zwrotów na poziomie pozycji.
- `purchase` może zostać zarejestrowany dla zamówienia anulowanego: GA4 pokazuje wydarzenie interfejsu, a baza stan rozliczenia. Takie przypadki są osobną rozbieżnością biznesową.
- Zdarzenia GA4 są **event-level**, pozycje event-items są **item-level**; po JOIN licz transakcje przez `count(DISTINCT transaction_id)`, a nie `count(*)`.
- Tożsamość `user_pseudo_id` nie zawsze oznacza jednego klienta, a część sesji nie ma `id_customer`. Dane nie są wzorem rzeczywistej polityki prywatności sklepu.
- Sezonowość popytu jest uproszczona; większa intensywność marketingu w okresach promocyjnych wynika z kosztów kampanii, ale nie musi automatycznie odzwierciedlać proporcjonalnego wzrostu sprzedaży. **Nie traktuj symulacji jako empirycznych benchmarków branżowych.**
- Stany końcowe magazynu pozostają nieujemne; model nie obejmuje wszystkich zdarzeń rzeczywistego WMS, np. rezerwacji czasowych, korekt inwentaryzacyjnych i transferów.

## Wbudowane anomalie (nie zaglądaj do klucza przed ćwiczeniem)

Zdarzenia `purchase` bywają nieobecne, zduplikowane lub zawierają błędny `transaction_id`; mogą też nie zawierać wszystkich pozycji. W zbiorze są również sesje botów (`is_bot=1`), anonimowi użytkownicy oraz anulacje i zwroty. `_anomaly_answer_key.json` zawiera dokładne identyfikatory wstrzykniętych przypadków; **nie jest to komplet wszystkich różnic między źródłami**, bo różnice wynikają też z odmiennych definicji metryk.

## Zadania analityczne

1. Policz GMV, obrót brutto i netto, AOV, liczbę zamówień dziennie / miesięcznie i porównaj wyniki w rozbiciu na status.
2. Wylicz marżę brutto na pozycjach, uwzględniając koszt zakupu (`purchase_supplier_price`) i rabaty. Oddziel marżę po dostawie od marży zamówień anulowanych.
3. Policz zwroty jednostkowe i finansowe per kategoria / rozmiar; zbadaj wpływ zwrotów na LTV.
4. Zbuduj kohorty według **pierwszego opłaconego zamówienia** i 12-miesięczną retencję klientów.
5. Zaimplementuj RFM dla klientów płacących i oblicz LTV historyczne.
6. Zbuduj sesyjny lejek `session_start → view_item → add_to_cart → begin_checkout → purchase`. Wykorzystaj `COUNT(DISTINCT session_id)` i usuń boty.
7. Porównaj przypisanie źródła GA4 do zamówień, zwróć uwagę na anulacje i brak `purchase`.
8. Policz ROAS dla płatnych kampanii jako obrót z zamówień połączonych z sesjami vs. koszt dzienny. Zdefiniuj, czy porównujesz kwoty brutto/netto oraz okres kliknięcia czy zakupu.
9. Policz CAC (koszt / nowi klienci), ale zdefiniuj nowych klientów na podstawie pierwszego **opłaconego zamówienia**, nie na podstawie `ps_customer.date_add`.
10. Wykryj brakujące `purchase`, nieznane transaction_id i duplikaty dla tej samej referencji.
11. Wykryj niekompletne koszyki zdarzeń `purchase` względem `ps_order_detail` na poziomie wariantów.
12. Odtwórz stan końcowy z `inventory_movements` i porównaj do `ps_stock_available`.
13. Sprawdź, czy jakiekolwiek warianty mają ujemny zapas; wyznacz produkty z najniższą dostępnością i największą sprzedażą.
14. Zbuduj model gwiazdy: `fact_order_item`, `fact_web_event`, `dim_product_variant`, `dim_customer`, `dim_campaign`, `dim_date`.
15. Zaproponuj codzienny test jakości danych w SQL: odsetek zamówień z `purchase`, odsetek zdublowanych zakupów, udział niezmapowanych referencji, zgodność wartości produktów.

## Ostrzeżenia techniczne

- `ps_cart` ma mniej niż 38 tys. rekordów: część wylosowanych sesji koszykowych symuluje boty, które kończą sesję przed dodaniem do koszyka.
- `ps_cart_product` i `ps_order_detail` odzwierciedlają finalną zawartość koszyka / zamówienia, nie pełną chronologię zmian ilości.
- Pliki CSV używają UTF-8, przecinka jako separatora i kropki dziesiętnej. Puste wartości to NULL.
- `ga4_events.event_timestamp` to tekst lokalnej daty i godziny, **nie** mikrosekundy UTC jak w oryginalnym eksporcie GA4 BigQuery.
