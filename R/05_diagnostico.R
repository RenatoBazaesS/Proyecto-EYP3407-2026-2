# 05_diagnostico.R — análisis de sensibilidad y estabilidad, sólo con desarrollo (2021-2022)
#
# Pregunta: ¿cambia la conclusión si se modifica una decisión del análisis?
# Los hiperparámetros quedan fijos en los elegidos por 03_modelos.R, de modo que cada
# diferencia proviene de la decisión modificada. Salidas: sensibilidad.csv y estabilidad_borough.
suppressPackageStartupMessages({
  library(tidymodels)
  library(dplyr)
  library(readr)
})
tidymodels_prefer(quiet = TRUE)
set.seed(3407)

# Reajusta una familia con sus hiperparámetros ya elegidos, ventana por ventana.
# 'predictores' define la información usada; 'conservar' limita las filas de entrenamiento
# y validación. La referencia se recalcula con las mismas filas de cada escenario.
evaluar_escenario <- function(escenario, predictores, conservar = NULL) {
  bind_rows(lapply(names(familias), function(m) {
    f <- familias[[m]]
    r <- resultados_ajuste[[m]]
    bind_rows(lapply(names(ventanas), function(n) {
      v <- ventanas[[n]]
      entrena <- v$entrena; valida <- v$valida
      if (!is.null(conservar)) {
        entrena <- intersect(entrena, conservar)
        valida  <- intersect(valida, conservar)
      }
      set.seed(3407)
      ajuste <- workflow() |>
        add_recipe(crear_receta(dev[entrena, ], predictores, f$normalizar)) |>
        add_model(finalize_model(f$espec, r$mejor)) |>
        fit(data = dev[entrena, ])
      p <- predict(ajuste, dev[valida, ], type = "prob")$.pred_sin_cierre
      y <- base_modelo$Y[valida]
      p_ref <- mean(base_modelo$Y[entrena])
      tibble(
        escenario = escenario, modelo = r$nombre, ventana = n, n = length(y),
        log_loss = mean(log_loss_vec(y, p)),
        log_loss_ref = mean(log_loss_vec(y, p_ref)),
        auc = auc_vec(y, p)
      )
    }))
  }))
}

# Base: mismos hiperparámetros y todos los predictores.
s_base <- evaluar_escenario("Base", predictores_modelo)

# Sensibilidad 1 (representación): retirar todo el historial.
s_sin_hist <- evaluar_escenario("S1: sin historial", pred_ingreso)

# Sensibilidad 2 (población): colapsar solicitudes repetidas por inmueble.
# Se retira una solicitud si el mismo bbl y descriptor tuvo otra en los 7 días previos.
repetidas <- base_modelo |>
  mutate(fila = row_number()) |>
  filter(fila %in% filas_dev) |>
  group_by(bbl, descriptor) |>
  mutate(repetida = !is.na(bbl) & !is.na(dplyr::lag(t_seg)) & (t_seg - dplyr::lag(t_seg)) <= 7 * 86400) |>
  ungroup()
filas_sin_repetidas <- repetidas$fila[!repetidas$repetida]
pct_repetidas <- 100 * mean(repetidas$repetida)
message(sprintf("Solicitudes repetidas retiradas en S2: %.1f%%", pct_repetidas))
s_colapsado <- evaluar_escenario("S2: sin repetidas por inmueble", predictores_modelo, filas_sin_repetidas)

sensibilidad_detalle <- bind_rows(s_base, s_sin_hist, s_colapsado)
write_csv(sensibilidad_detalle, "output/tablas/sensibilidad_por_ventana.csv")

tabla_sensibilidad <- sensibilidad_detalle |>
  mutate(dif = log_loss - log_loss_ref) |>
  group_by(escenario, modelo) |>
  summarise(
    n_validacion = sum(n),
    log_loss = mean(log_loss),
    dif_vs_ref = mean(dif),
    auc = mean(auc),
    .groups = "drop"
  ) |>
  arrange(escenario, log_loss) |>
  group_by(escenario) |>
  mutate(mejor_del_escenario = log_loss == min(log_loss)) |>
  ungroup() |>
  mutate(pct_repetidas_retiradas = ifelse(startsWith(escenario, "S2"), round(pct_repetidas, 1), NA_real_))
print(tabla_sensibilidad)
write_csv(tabla_sensibilidad, "output/tablas/sensibilidad.csv")

# Estabilidad del modelo elegido entre boroughs dentro de la validación.
estabilidad_borough <- pred_validacion |>
  filter(modelo %in% c(modelo_elegido, "Referencia: tasa histórica")) |>
  mutate(borough = as.character(base_modelo$borough[fila])) |>
  filter(!is.na(borough), borough != "Unspecified") |>
  mutate(perdida = log_loss_vec(y, p), rol = ifelse(startsWith(modelo, "Ref"), "ref", "elegido")) |>
  group_by(borough, rol) |>
  summarise(n = n(), prevalencia = mean(y), log_loss = mean(perdida), .groups = "drop") |>
  pivot_wider(names_from = rol, values_from = log_loss) |>
  mutate(dif_vs_ref = elegido - ref)
print(estabilidad_borough)
write_csv(estabilidad_borough, "output/tablas/estabilidad_borough_desarrollo.csv")
