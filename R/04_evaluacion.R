# 04_evaluacion.R — comparación en desarrollo, regla de selección y umbral
#
# Reúne las predicciones de validación, compara modelos sobre las mismas filas, elige
# un modelo y fija su umbral. Todo ocurre antes de examinar la reserva 2023.
# Requiere 02 y 03. Salidas: comparacion_desarrollo.csv, seleccion.csv, seleccion.rds.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})

# --- 1. Predicciones de validación por modelo ----------------------------
# La referencia usa la tasa observada en el entrenamiento de cada ventana.
pred_ref <- bind_rows(lapply(names(ventanas), function(n) {
  v <- ventanas[[n]]
  tibble(
    ventana = n, fila = v$valida, modelo = "Referencia: tasa histórica",
    p = mean(base_modelo$Y[v$entrena])
  )
}))

pred_mod <- bind_rows(lapply(resultados_ajuste, function(r) {
  tibble(ventana = r$pred$id, fila = r$pred$.row, modelo = r$nombre, p = r$pred$.pred_sin_cierre)
}))

pred_validacion <- bind_rows(pred_ref, pred_mod) |>
  mutate(y = base_modelo$Y[fila])

# Comparación pareada: todos los modelos deben evaluarse en las mismas filas.
stopifnot(
  pred_validacion |> count(modelo, ventana) |> count(ventana, n) |> count(ventana) |> pull(n) |> max() == 1
)

# --- 2. Métricas por ventana y resumen ----------------------------------
por_ventana <- pred_validacion |>
  group_by(modelo, ventana) |>
  group_modify(~ metricas(.x$y, .x$p)) |>
  ungroup()
write_csv(por_ventana, "output/tablas/desarrollo_por_ventana.csv")

# dif_vs_ref < 0 significa que el modelo mejora a la referencia. dif_min y dif_max
# muestran la variación entre ventanas, que no es un intervalo de confianza.
ll_ref_ventana <- por_ventana |>
  filter(startsWith(modelo, "Referencia")) |>
  select(ventana, ll_ref = log_loss)

comparacion_dev <- por_ventana |>
  left_join(ll_ref_ventana, by = "ventana") |>
  mutate(dif = log_loss - ll_ref) |>
  group_by(modelo) |>
  summarise(
    n_validacion = sum(n),
    prevalencia = weighted.mean(prevalencia, n),
    log_loss = mean(log_loss),
    dif_vs_ref = mean(dif),
    dif_min = min(dif),
    dif_max = max(dif),
    brier = mean(brier),
    auc = mean(auc),
    .groups = "drop"
  ) |>
  arrange(log_loss)
print(comparacion_dev)

# --- 3. Regla de selección (fijada antes de mirar la reserva) ------------
# Menor log-loss medio. Si un modelo más simple queda a menos de 0.002 del
# mejor, se prefiere el más simple. Orden de complejidad: M1 < M2 < M3.
TOLERANCIA <- 0.002
orden_modelos <- c("M1: logística lasso", "M2: árbol podado", "M3: boosting")
candidatos <- comparacion_dev |>
  filter(modelo %in% orden_modelos) |>
  mutate(orden = match(modelo, orden_modelos))
mejor_ll <- min(candidatos$log_loss)
modelo_elegido <- candidatos |>
  filter(log_loss <= mejor_ll + TOLERANCIA) |>
  slice_min(orden, n = 1) |>
  pull(modelo)
clave_elegido <- names(familias)[sapply(familias, function(f) f$nombre) == modelo_elegido]
message("Modelo elegido en desarrollo: ", modelo_elegido)

# --- 4. Umbral fijado en desarrollo (Youden sobre validación agrupada) ---
# El índice de Youden (sensibilidad + especificidad - 1) da igual peso a ambos errores.
# Se evalúa en los percentiles 2 a 98 de p para no elegir cortes con casi ningún caso.
umbral_youden <- function(y, p) {
  cortes <- quantile(p, probs = seq(0.02, 0.98, by = 0.01), names = FALSE) |> unique()
  j <- sapply(cortes, function(u) {
    m <- metricas_umbral(y, p, u)
    m$sensibilidad + m$especificidad - 1
  })
  cortes[which.max(j)]
}

umbrales <- pred_validacion |>
  filter(modelo %in% orden_modelos) |>
  group_by(modelo) |>
  summarise(umbral = umbral_youden(y, p), .groups = "drop")

umbral_elegido <- umbrales$umbral[umbrales$modelo == modelo_elegido]

umbral_dev <- pred_validacion |>
  inner_join(umbrales, by = "modelo") |>
  group_by(modelo) |>
  group_modify(~ metricas_umbral(.x$y, .x$p, .x$umbral[1])) |>
  ungroup()

tabla_dev <- comparacion_dev |>
  left_join(select(umbral_dev, modelo, umbral, sensibilidad, vpp), by = "modelo")
print(tabla_dev)
write_csv(tabla_dev, "output/tablas/comparacion_desarrollo.csv")

saveRDS(
  list(modelo = modelo_elegido, clave = clave_elegido, umbral = umbral_elegido,
       umbrales = umbrales, tolerancia = TOLERANCIA),
  "output/seleccion.rds"
)
write_csv(
  tibble(modelo_elegido = modelo_elegido, umbral = umbral_elegido, tolerancia = TOLERANCIA),
  "output/tablas/seleccion.csv"
)
