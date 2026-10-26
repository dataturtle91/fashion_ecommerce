# Miesieczna liczba zamowien i zgloszen zwrotow, 2025-10 -- 2026-09.
# Wymagane pakiety:
# install.packages(c("DBI", "duckdb", "ggplot2"))
# Uruchomienie z katalogu projektu: Rscript R/orders_returns_monthly.R
# W RStudio: source("R/orders_returns_monthly.R") z katalogu projektu.
# Opcjonalnie przekaz katalog projektu jako pierwszy argument Rscript.

main <- function() {
  required <- c("DBI", "duckdb", "ggplot2")
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
  # Wspolna os czasu i wspolna skala liczebnosci dla obu serii.
  line_data <- data.frame(
    miesiac = rep(as.Date(paste0(result$miesiac, "-01")), 2),
    liczba = c(result$liczba_zamowien, result$liczba_zwrotow),
    seria = rep(c("Zamówienia", "Zgłoszenia zwrotów"), each = nrow(result))
  )
  month_dates <- as.Date(paste0(result$miesiac, "-01"))
  month_labels <- c("paź\n2025", "lis", "gru", "sty\n2026", "lut", "mar",
                    "kwi", "maj", "cze", "lip", "sie", "wrz")
  palette <- c("Zamówienia" = "#176B70", "Zgłoszenia zwrotów" = "#C46C46")
  format_count <- function(x) format(x, big.mark = " ", scientific = FALSE, trim = TRUE)

  line_plot <- ggplot2::ggplot(
    line_data,
    ggplot2::aes(x = miesiac, y = liczba, colour = seria, group = seria)
  ) +
    ggplot2::geom_line(linewidth = 1.2, lineend = "round") +
    ggplot2::geom_point(shape = 21, fill = "#FAF9F6", size = 3, stroke = 1.2) +
    ggplot2::scale_colour_manual(values = palette, breaks = names(palette)) +
    ggplot2::scale_x_date(
      breaks = month_dates, labels = month_labels,
      expand = ggplot2::expansion(mult = c(0.025, 0.025))
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, NA), labels = format_count,
      expand = ggplot2::expansion(mult = c(0.02, 0.12))
    ) +
    ggplot2::labs(
      title = "Rok w zamówieniach i zwrotach",
      subtitle = paste0(
        "PAŹ 2025 — WRZ 2026   •   ",
        format_count(sum(result$liczba_zamowien)), " zamówień   /   ",
        format_count(sum(result$liczba_zwrotow)), " zgłoszeń zwrotów"
      ),
      x = NULL, y = "Liczba w miesiącu", colour = NULL,
      caption = paste0(
        "Zamówienia obejmują wszystkie statusy, w tym anulacje. Zwroty oznaczają zgłoszenia, nie sztuki.\n",
        "Każda seria według własnej daty rejestracji; zwrot może dotyczyć wcześniejszego zamówienia.\n",
        "Źródło: FashionCommerce • dane syntetyczne"
      )
    ) +
    ggplot2::theme_minimal(base_size = 12, base_family = "sans") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "#FAF9F6", colour = NA),
      panel.background = ggplot2::element_rect(fill = "#FAF9F6", colour = NA),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = "#E3E5E1", linewidth = 0.35),
      plot.title = ggplot2::element_text(size = 25, face = "bold", colour = "#203438",
                                       margin = ggplot2::margin(b = 12)),
      plot.subtitle = ggplot2::element_text(size = 11, colour = "#617173",
                                          margin = ggplot2::margin(b = 18)),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.caption = ggplot2::element_text(hjust = 0, size = 9, lineheight = 1.4,
                                         colour = "#6E7979", margin = ggplot2::margin(t = 20)),
      axis.text = ggplot2::element_text(colour = "#526366", size = 11),
      axis.text.x = ggplot2::element_text(margin = ggplot2::margin(t = 10)),
      axis.title.y = ggplot2::element_text(colour = "#617173", size = 10,
                                         margin = ggplot2::margin(r = 12)),
      legend.position = "top",
      legend.justification = "left",
      legend.text = ggplot2::element_text(colour = "#203438", size = 11),
      legend.key.width = grid::unit(1.2, "cm"),
      plot.margin = ggplot2::margin(25, 30, 20, 25)
    )

  ggplot2::ggsave(
    file.path(reports_dir, "orders_returns_monthly_line.png"),
    plot = line_plot, width = 12, height = 7, dpi = 300, bg = "#FAF9F6"
  )

  summary_lines <- c(
    "ZAMÓWIENIA I ZWROTY — PODSUMOWANIE MIESIĘCZNE",
    "Okres: październik 2025 – wrzesień 2026",
    "",
    sprintf(
      "%s | Zamówienia: %s | Zgłoszenia zwrotów: %s",
      result$miesiac,
      format_count(result$liczba_zamowien),
      format_count(result$liczba_zwrotow)
    ),
    "",
    sprintf(
      "Łącznie | Zamówienia: %s | Zgłoszenia zwrotów: %s",
      format_count(sum(result$liczba_zamowien)),
      format_count(sum(result$liczba_zwrotow))
    ),
    "",
    "Zamówienia obejmują wszystkie statusy, w tym anulacje.",
    "Zwroty to liczba zgłoszeń, nie liczba zwróconych sztuk ani refundacji.",
    "Każda seria jest przypisana do miesiąca własnej rejestracji.",
    "Zwroty mogą dotyczyć zamówień z wcześniejszych miesięcy."
  )
  writeLines(
    enc2utf8(summary_lines),
    file.path(reports_dir, "orders_returns_monthly_summary.txt"),
    useBytes = TRUE
  )
  cat(paste(summary_lines, collapse = "\n"), "\n")
  if (interactive()) print(line_plot)
  invisible(line_plot)
}

monthly_plot <- main()
