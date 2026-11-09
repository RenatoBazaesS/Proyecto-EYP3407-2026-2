# 06_reserva.R — evaluación final única en la reserva 2023
# Modelos, hiperparámetros, regla de selección y umbral vienen fijados de desarrollo.
#
# Aquí no se elige nada: se reajusta con los datos permitidos, se predice 2023 y se informa.
# Los resultados no deben usarse para cambiar modelos, variables o umbrales. Si se
# corrige un error después de ver estos resultados, el informe debe explicarlo (§4.1).
# Salidas: comparacion_reserva.csv, matriz de confusión, calibración, incertidumbre,
# errores por subgrupo, extremos y figuras de calibración y diagnóstico.
suppressPackageStartupMessages({
  library(tidymodels)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
})
tidymodels_prefer(quiet = TRUE)
set.seed(3407)

datos_modelo <- base_modelo[, c("unique_key", "Yf", predictores_modelo)]
entrena <- final_reserva$entrena
prueba  <- final_reserva$valida
y_prueba <- base_modelo$Y[prueba]

# --- 1. Reajuste con los datos permitidos y predicción -------------------
p_reserva <- lapply(names(familias), function(m) {
  f <- familias[[m]]
  set.seed(3407)
  ajuste <- workflow() |>
    add_recipe(crear_receta(datos_modelo[entrena, ], predictores_modelo, f$normalizar)) |>
    add_model(finalize_model(f$espec, resultados_ajuste[[m]]$mejor)) |>
    fit(data = datos_modelo[entrena, ])
  predict(ajuste, datos_modelo[prueba, ], type = "prob")$.pred_sin_cierre
})
names(p_reserva) <- sapply(familias, function(f) f$nombre)
p_reserva[["Referencia: tasa histórica"]] <- rep(mean(base_modelo$Y[entrena]), length(prueba))

predicciones <- tibble(unique_key = base_modelo$unique_key[prueba], y = y_prueba) |>
  bind_cols(as_tibble(p_reserva))
saveRDS(predicciones, "output/predicciones_reserva.rds")

# --- 2. Tabla comparativa en reserva --------------------------------------
ll_ref <- mean(log_loss_vec(y_prueba, p_reserva[["Referencia: tasa histórica"]]))
tabla_reserva <- bind_rows(lapply(names(p_reserva), function(m) {
  res <- metricas(y_prueba, p_reserva[[m]]) |> mutate(modelo = m, dif_vs_ref = log_loss - ll_ref)
  u <- umbrales$umbral[umbrales$modelo == m]
  if (length(u) == 1) {
    res <- bind_cols(res, metricas_umbral(y_prueba, p_reserva[[m]], u) |> select(umbral, sensibilidad, vpp))
  }
  res
})) |>
  select(modelo, n, prevalencia, log_loss, dif_vs_ref, brier, auc, any_of(c("umbral", "sensibilidad", "vpp"))) |>
  arrange(log_loss)
print(tabla_reserva)
write_csv(tabla_reserva, "output/tablas/comparacion_reserva.csv")

p_elegido <- p_reserva[[modelo_elegido]]
p_ref <- p_reserva[["Referencia: tasa histórica"]]

# --- 3. Matriz de confusión del modelo elegido ---------------------------
conf <- metricas_umbral(y_prueba, p_elegido, umbral_elegido)
matriz <- tibble(
  `Observado` = c("Sin cierre a 7 días (Y = 1)", "Con cierre a 7 días (Y = 0)"),
  `Predicho sin cierre` = c(conf$VP, conf$FP),
  `Predicho con cierre` = c(conf$FN, conf$VN)
)
print(matriz)
write_csv(matriz, "output/tablas/matriz_confusion_reserva.csv")
write_csv(conf, "output/tablas/umbral_reserva.csv")

# --- 4. Calibración ------------------------------------------------------
calib <- tibble(p = p_elegido, y = y_prueba) |>
  mutate(grupo = ntile(p, 10)) |>
  group_by(grupo) |>
  summarise(n = n(), p_media = mean(p), y_media = mean(y), .groups = "drop")
write_csv(calib, "output/tablas/calibracion_reserva.csv")

logit <- function(x) log(x / (1 - x))
ajuste_calib <- glm(y_prueba ~ logit(pmin(pmax(p_elegido, 1e-6), 1 - 1e-6)), family = binomial)
calib_resumen <- tibble(intercepto = coef(ajuste_calib)[1], pendiente = coef(ajuste_calib)[2])
write_csv(calib_resumen, "output/tablas/calibracion_resumen.csv")

fig_calib <- ggplot(calib, aes(p_media, y_media)) +
  geom_abline(linetype = 2, colour = "grey55") +
  geom_line(colour = "#3B6FB6") + geom_point(aes(size = n), colour = "#3B6FB6") +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  scale_size_continuous(guide = "none") +
  labs(x = "Probabilidad predicha media", y = "Proporción observada sin cierre a 7 días") +
  theme_minimal(base_size = 10)
ggsave("output/figuras/calibracion.png", fig_calib, width = 4.2, height = 4.2, dpi = 200)

# --- 5. Incertidumbre de la diferencia frente a la referencia -------------
# Predicciones fijas: condicional a los ajustes, sin propagar selección ni entrenamiento.
B <- 2000
perdida_dif <- log_loss_vec(y_prueba, p_elegido) - log_loss_vec(y_prueba, p_ref)

# Se remuestrean unidades completas, no filas, porque las solicitudes de un mismo
# inmueble o distrito no son independientes. Basta con sumar las pérdidas por unidad.
bootstrap_cluster <- function(valores, cluster, B) {
  g <- match(cluster, unique(cluster))
  sumas <- as.numeric(rowsum(valores, g)); ns <- as.numeric(rowsum(rep(1, length(g)), g))
  K <- length(sumas)
  vapply(seq_len(B), function(i) {
    s <- sample.int(K, K, replace = TRUE)
    sum(sumas[s]) / sum(ns[s])
  }, numeric(1))
}

clave_bbl <- ifelse(is.na(base_modelo$bbl[prueba]),
                    paste0("sin_bbl_", base_modelo$unique_key[prueba]),
                    as.character(base_modelo$bbl[prueba]))
clave_cb <- as.character(base_modelo$community_board[prueba])
clave_cb[is.na(clave_cb)] <- "faltante"

# Bloques temporales: también dependen entre sí las solicitudes de un mismo periodo.
# Con sólo 12 meses el intervalo es aproximado; las semanas dan más bloques.
clave_semana <- format(base_modelo$created_date[prueba], "%G-%V")
clave_mes    <- format(base_modelo$created_date[prueba], "%Y-%m")

unidades <- list(
  "Inmueble (bbl)" = clave_bbl,
  "Distrito comunitario" = clave_cb,
  "Semana de ingreso" = clave_semana,
  "Mes de ingreso" = clave_mes
)
incertidumbre <- bind_rows(lapply(names(unidades), function(u) {
  set.seed(3407)
  boot <- bootstrap_cluster(perdida_dif, unidades[[u]], B)
  tibble(
    unidad_remuestreada = u,
    n_unidades = n_distinct(unidades[[u]]),
    replicas = B,
    dif_log_loss = mean(perdida_dif),
    ic95_inf = unname(quantile(boot, 0.025)),
    ic95_sup = unname(quantile(boot, 0.975))
  )
}))
print(incertidumbre)
write_csv(incertidumbre, "output/tablas/incertidumbre_reserva.csv")

# --- 6. Errores por subgrupo y periodo ------------------------------------
detalle <- tibble(
  y = y_prueba, p = p_elegido, p_ref = p_ref,
  distrito = as.character(base_modelo$council_district[prueba]),
  mes = format(base_modelo$created_date[prueba], "%Y-%m"),
  canal = as.character(base_modelo$open_data_channel_type[prueba]),
  descriptor = as.character(base_modelo$descriptor[prueba]),
  perdida = log_loss_vec(y_prueba, p_elegido),
  perdida_ref = log_loss_vec(y_prueba, p_ref)
)

resumen_grupo <- function(datos, variable) {
  datos |>
    filter(!is.na(.data[[variable]])) |>
    group_by(nivel = .data[[variable]]) |>
    summarise(
      n = n(), prevalencia = mean(y), p_media = mean(p),
      log_loss = mean(perdida), log_loss_ref = mean(perdida_ref),
      .groups = "drop"
    ) |>
    mutate(dif_vs_ref = log_loss - log_loss_ref, grupo = variable, .before = 1)
}
subgrupos <- bind_rows(lapply(c("distrito", "mes", "canal", "descriptor"), resumen_grupo, datos = detalle))
write_csv(subgrupos, "output/tablas/errores_subgrupos_reserva.csv")

panel <- function(g, titulo) {
  subgrupos |>
    filter(grupo == g, n >= 30) |>
    mutate(nivel = reorder(nivel, dif_vs_ref)) |>
    ggplot(aes(dif_vs_ref, nivel, size = n)) +
    geom_vline(xintercept = 0, linetype = 2, colour = "grey55") +
    geom_point(colour = "#3B6FB6") +
    scale_size_continuous(range = c(0.8, 3.5), name = "Solicitudes") +
    labs(title = titulo, x = "Log-loss modelo − referencia", y = NULL) +
    theme_minimal(base_size = 8)
}
fig_diag <- (panel("distrito", "Distrito municipal") | panel("mes", "Mes de ingreso") |
               (panel("canal", "Canal") / panel("descriptor", "Detalle"))) +
  plot_layout(guides = "collect") & theme(legend.position = "bottom")
ggsave("output/figuras/diagnostico_subgrupos.png", fig_diag, width = 7.2, height = 5.6, dpi = 200)

# --- 7. Extremos --------------------------------------------------------
extremos <- detalle |>
  mutate(tipo = case_when(
    p >= 0.9 & y == 0 ~ "Muy probable sin cierre, pero cerró (p >= 0.9, Y = 0)",
    p <= 0.1 & y == 1 ~ "Muy probable cierre, pero no cerró (p <= 0.1, Y = 1)",
    TRUE ~ NA_character_
  )) |>
  filter(!is.na(tipo)) |>
  count(tipo, descriptor, name = "n") |>
  arrange(tipo, desc(n))
# Se compara lo predicho con lo observado en las colas de la distribución de p.
corte_alto <- unname(quantile(p_elegido, 0.99))
corte_bajo <- unname(quantile(p_elegido, 0.01))
resumir_cola <- function(nombre, filas) {
  tibble(
    grupo = nombre, n = sum(filas),
    p_media = if (any(filas)) mean(p_elegido[filas]) else NA_real_,
    tasa_observada = if (any(filas)) mean(y_prueba[filas]) else NA_real_
  )
}
extremos_resumen <- bind_rows(
  resumir_cola("1% con mayor probabilidad", p_elegido >= corte_alto),
  resumir_cola("1% con menor probabilidad", p_elegido <= corte_bajo),
  resumir_cola("p >= 0,9", p_elegido >= 0.9),
  resumir_cola("p <= 0,1", p_elegido <= 0.1)
)
print(extremos_resumen)
write_csv(extremos, "output/tablas/extremos_reserva.csv")
write_csv(extremos_resumen, "output/tablas/extremos_resumen_reserva.csv")

# Detalles poco frecuentes: menos de 1% de la reserva. Con pocos casos, el error
# del modelo se estima con poca precisión y la recomendación es menos confiable.
detalles_raros <- subgrupos |>
  filter(grupo == "descriptor", n < 0.01 * length(prueba)) |>
  select(-grupo) |>
  arrange(n)
print(detalles_raros)
write_csv(detalles_raros, "output/tablas/detalles_raros_reserva.csv")
