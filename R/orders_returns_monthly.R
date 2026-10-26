# Miesieczna liczba zamowien i zgloszen zwrotow, 2025-10 -- 2026-09.
# Wymagane pakiety:
# install.packages(c("DBI", "duckdb", "ggplot2", "plotly", "htmlwidgets"))
# Uruchomienie z katalogu projektu: Rscript R/orders_returns_monthly.R
# W RStudio: source("R/orders_returns_monthly.R") z katalogu projektu.
# Opcjonalnie przekaz katalog projektu jako pierwszy argument Rscript.

main <- function() {
  required <- c("DBI", "duckdb", "ggplot2", "plotly", "htmlwidgets")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Zainstaluj wymagane pakiety: install.packages(c(",
         paste(sprintf('"%s"', missing), collapse = ", "), "))", call. = FALSE)
  }

  args <- commandArgs(trailingOnly = TRUE)
  script_arg <- grep("^--file=", commandArgs(), value = TRUE)
  project_dir <- if (length(args)) {
    args[[1]]
  } else if (length(script_arg)) {
    file.path(dirname(sub("^--file=", "", script_arg[[1]])), "..")
  } else if (file.exists("db/fashion.duckdb")) {
    "."
  } else {
    ".."
  }
  project_dir <- normalizePath(project_dir, mustWork = TRUE)
  db_path <- file.path(project_dir, "db", "fashion.duckdb")
  if (!file.exists(db_path)) stop("Nie znaleziono bazy: ", db_path)

  # Tryb tylko do odczytu chroni dane zrodlowe.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Agregujemy obie tabele osobno, aby nie mnozyc zamowien przez zwroty.
  # Zamowienia: wszystkie statusy (rowniez anulowane), wedlug date_add.
  # Zwroty: unikalne zgloszenia id_order_return, wedlug daty zwrotu.
  # Zwrot czesciowy jest jednym zgloszeniem, a nie zwrotem calego zamowienia.
  # Nie filtrujemy stanu zgloszenia; to nie jest liczba refundacji ani sztuk.
  query <- "
    WITH months AS (
      SELECT CAST(month AS DATE) AS month
      FROM generate_series(DATE '2025-10-01', DATE '2026-09-01',
                           INTERVAL '1 month') AS t(month)
    ), orders AS (
      SELECT date_trunc('month', CAST(date_add AS TIMESTAMP)) AS month,
             count(DISTINCT id_order) AS order_count
      FROM ps_orders
      WHERE CAST(date_add AS TIMESTAMP) >= TIMESTAMP '2025-10-01'
        AND CAST(date_add AS TIMESTAMP) < TIMESTAMP '2026-10-01'
      GROUP BY 1
    ), returns AS (
      SELECT date_trunc('month', CAST(date_add AS TIMESTAMP)) AS month,
             count(DISTINCT id_order_return) AS return_count
      FROM ps_order_return
      WHERE CAST(date_add AS TIMESTAMP) >= TIMESTAMP '2025-10-01'
        AND CAST(date_add AS TIMESTAMP) < TIMESTAMP '2026-10-01'
      GROUP BY 1
    )
    SELECT strftime(m.month, '%Y-%m') AS month,
           CAST(coalesce(o.order_count, 0) AS INTEGER) AS order_count,
           CAST(coalesce(r.return_count, 0) AS INTEGER) AS return_count
    FROM months m
    LEFT JOIN orders o USING (month)
    LEFT JOIN returns r USING (month)
    ORDER BY m.month
  "
  result <- DBI::dbGetQuery(con, query)
  names(result) <- c("miesiac", "liczba_zamowien", "liczba_zwrotow")
  stopifnot(nrow(result) == 12L, !anyNA(result),
            all(result$liczba_zamowien >= 0), all(result$liczba_zwrotow >= 0))

  reports_dir <- file.path(project_dir, "R", "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(result, file.path(reports_dir, "orders_returns_monthly.csv"),
            row.names = FALSE, fileEncoding = "UTF-8")

  # Oddzielne panele pozwalaja odczytac mniejsza liczbe zwrotow.
  grDevices::svg(file.path(reports_dir, "orders_returns_monthly.svg"),
                 width = 12, height = 8)
  tryCatch({
    par(mfrow = c(2, 1), mar = c(5, 5, 3, 1))
    barplot(result$liczba_zamowien, names.arg = result$miesiac,
            col = "#2563EB", border = NA, las = 2,
            main = "Zamowienia wedlug miesiaca utworzenia (wszystkie statusy)",
            ylab = "Liczba zamowien")
    barplot(result$liczba_zwrotow, names.arg = result$miesiac,
            col = "#EA580C", border = NA, las = 2,
            main = "Zgloszenia zwrotow wedlug miesiaca rejestracji",
            ylab = "Liczba zgloszen zwrotow")
  }, finally = grDevices::dev.off())

  # Wspolna os czasu i wspolna skala liczebnosci dla obu serii.
  line_data <- data.frame(
    miesiac = rep(as.Date(paste0(result$miesiac, "-01")), 2),
    liczba = c(result$liczba_zamowien, result$liczba_zwrotow),
    seria = rep(c("Zamówienia", "Zgłoszenia zwrotów"), each = nrow(result))
  )
  line_plot <- ggplot2::ggplot(
    line_data,
    ggplot2::aes(x = miesiac, y = liczba, colour = seria, group = seria)
  ) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_colour_manual(
      values = c("Zamówienia" = "#2563EB", "Zgłoszenia zwrotów" = "#EA580C")
    ) +
    ggplot2::scale_x_date(date_breaks = "1 month", date_labels = "%Y-%m") +
    ggplot2::scale_y_continuous(limits = c(0, NA)) +
    ggplot2::labs(
      title = "Miesięczna liczba zamówień i zwrotów",
      subtitle = "Zamówienia: wszystkie statusy. Zwroty: liczba zgłoszeń.",
      x = "Miesiąc", y = "Liczba", colour = NULL,
      caption = "Według dat utworzenia zamówień i rejestracji zwrotów."
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      legend.position = "bottom",
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
  ggplot2::ggsave(
    file.path(reports_dir, "orders_returns_monthly_line.png"),
    plot = line_plot, width = 12, height = 6, dpi = 160, bg = "white"
  )

  interactive_plot <- plotly::ggplotly(line_plot, tooltip = c("x", "y", "colour"))
  interactive_plot <- plotly::config(interactive_plot, displaylogo = FALSE)
  # HTML i katalog zaleznosci tworza komplet; zapis nie wymaga Pandoc.
  htmlwidgets::saveWidget(
    interactive_plot,
    file = file.path(reports_dir, "orders_returns_monthly_line.html"),
    selfcontained = FALSE
  )
  if (interactive()) {
    print(line_plot)
    print(interactive_plot)
  }

  print(result, row.names = FALSE)
  cat("\nLaczna liczba zamowien:", sum(result$liczba_zamowien),
      "\nLaczna liczba zgloszen zwrotow:", sum(result$liczba_zwrotow), "\n")
  cat("Zwroty moga dotyczyc zamowien z poprzednich miesiecy.\n",
      "Iloraz tych liczb nie jest kohortowa stopa zwrotow.\n",
      "Raporty zapisano w:", reports_dir, "\n")
  invisible(result)
}

monthly_analysis <- main()
