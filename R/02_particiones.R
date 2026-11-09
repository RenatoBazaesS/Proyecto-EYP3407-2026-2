# 02_particiones.R — predictores de ingreso, historial sin fuga y particiones temporales
#
# Entrada: output/datos_auditados.rds (creado por 01_preparacion.R).
# Salida:  output/particiones.rds, output/tablas/particiones.csv y el diagrama temporal.
# Deja en memoria, para los scripts siguientes: base_modelo, ventanas, final_reserva,
# las listas de predictores y las funciones de métricas.
#
# Idea central: cada solicitud sólo puede usar información conocida al ingresar, y
# cada entrenamiento sólo puede usar solicitudes cuya respuesta a 7 días ya se conocía.
suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(ggplot2)
})

set.seed(3407)
TZ_NY     <- "America/New_York"
HORIZONTE <- 168 * 3600            # 7 días en segundos
inicio_reserva <- as.POSIXct("2023-01-01 00:00:00", tz = TZ_NY)

base_auditada <- readRDS("output/datos_auditados.rds")

# --- 1. Predictores derivados de la fecha de ingreso --------------------
# El año se omite: 2023 no se observa en entrenamiento y sería una extrapolación.
base_modelo <- base_auditada |>
  arrange(created_date, unique_key) |>
  mutate(
    t_seg      = as.numeric(created_date),
    mes        = factor(sprintf("%02d", month(created_date))),
    dia_semana = factor(wday(created_date, week_start = 1)),
    hora       = factor(sprintf("%02d", hour(created_date))),
    across(
      c(descriptor, descriptor_2, borough, community_board, council_district,
        police_precinct, incident_zip, open_data_channel_type),
      ~ factor(as.character(.x))
    )
  )

# --- 2. Historial del área y del inmueble -------------------------------
# Volumen: solicitudes creadas estrictamente antes de t (conocidas al ingreso).
# Tasa: sólo solicitudes con horizonte de 7 días ya terminado en t
# (created_date + 168 h <= t), como exige la ficha del caso.
#
# La función recibe las solicitudes de un mismo distrito y devuelve dos valores por fila.
# findInterval(x, t) cuenta cuántos valores de t quedan a la izquierda de x, lo que
# permite contar solicitudes dentro de una ventana sin recorrer la base fila por fila.
# Con left.open = TRUE cuenta los valores estrictamente menores que x.
historial_grupo <- function(t, y) {
  # t debe venir ordenado de forma creciente
  dia <- 86400   # segundos en un día
  antes        <- findInterval(t, t, left.open = TRUE)        # n creadas < t
  antes_7d     <- findInterval(t - 7 * dia, t, left.open = TRUE)
  vol_7d       <- antes - antes_7d
  # Con la suma acumulada de Y, los casos de un tramo salen de restar dos posiciones.
  # El tramo termina en t - 168 h: las solicitudes más recientes aún no tienen respuesta.
  acum         <- c(0, cumsum(y))
  hasta       <- findInterval(t - HORIZONTE, t)              # horizonte terminado
  desde        <- findInterval(t - HORIZONTE - 90 * dia, t, left.open = TRUE)
  n_90d        <- hasta - desde
  tasa_90d     <- ifelse(n_90d > 0, (acum[hasta + 1] - acum[desde + 1]) / n_90d, NA_real_)
  list(vol_7d = vol_7d, tasa_90d = tasa_90d)
}

# Tres variables de historial: volumen reciente del distrito, tasa reciente del
# distrito sin cierre a 7 días y volumen reciente del mismo inmueble. El inmueble
# sólo aporta volumen, porque una tasa con tan pocas solicitudes sería muy inestable.
# Sin historial previo la tasa queda NA y se imputa dentro de la receta (03_modelos.R).
base_modelo <- base_modelo |>
  group_by(community_board) |>
  mutate(
    hist_vol_cb_7d   = historial_grupo(t_seg, Y)$vol_7d,
    hist_tasa_cb_90d = historial_grupo(t_seg, Y)$tasa_90d
  ) |>
  group_by(bbl) |>
  mutate(
    hist_vol_bbl_90d = {
      a <- findInterval(t_seg, t_seg, left.open = TRUE)
      b <- findInterval(t_seg - 90 * 86400, t_seg, left.open = TRUE)
      if (first(is.na(bbl))) NA_integer_ else a - b
    }
  ) |>
  ungroup()

pred_ingreso <- c(
  "mes", "dia_semana", "hora", "open_data_channel_type", "descriptor", "descriptor_2",
  "borough", "community_board", "council_district", "police_precinct", "incident_zip"
)
pred_historial <- c("hist_vol_cb_7d", "hist_tasa_cb_90d", "hist_vol_bbl_90d")
predictores_modelo <- c(pred_ingreso, pred_historial)

base_modelo <- base_modelo |>
  mutate(Yf = factor(ifelse(Y == 1, "sin_cierre", "cierre"), levels = c("sin_cierre", "cierre")))

# --- 3. Particiones -----------------------------------------------------
# Tres orígenes en 2022 con entrenamiento expansivo. Entrenamiento: creadas con
# created_date + 168 h <= origen, de modo que su respuesta ya es conocida.
# Las solicitudes de los 7 días previos al origen no se usan en esa ventana: al llegar
# el origen su respuesta todavía no se conocería. Devuelve posiciones de filas en base_modelo.
crear_particion <- function(origen, fin) {
  list(
    origen  = origen,
    fin     = fin,
    entrena = which(base_modelo$t_seg + HORIZONTE <= as.numeric(origen)),
    valida  = which(base_modelo$t_seg >= as.numeric(origen) & base_modelo$t_seg < as.numeric(fin))
  )
}

origenes <- as.POSIXct(c("2022-01-01", "2022-05-01", "2022-09-01", "2023-01-01"), tz = TZ_NY)
ventanas <- lapply(1:3, function(i) crear_particion(origenes[i], origenes[i + 1]))
names(ventanas) <- paste0("V", 1:3)

final_reserva <- crear_particion(inicio_reserva, as.POSIXct("2024-01-01", tz = TZ_NY))

# Comprobaciones de separación
invisible(lapply(c(ventanas, list(final_reserva)), function(v) {
  stopifnot(
    max(base_modelo$t_seg[v$entrena]) + HORIZONTE <= as.numeric(v$origen),
    length(intersect(v$entrena, v$valida)) == 0
  )
}))
stopifnot(!any(year(base_modelo$created_date[unlist(lapply(ventanas, `[[`, "valida"))]) == 2023))

resumen_particiones <- bind_rows(lapply(names(c(ventanas, list(Reserva = final_reserva))), function(n) {
  v <- c(ventanas, list(Reserva = final_reserva))[[n]]
  tibble(
    particion      = n,
    fin_entrena    = format(max(base_modelo$created_date[v$entrena]), "%Y-%m-%d"),
    n_entrena      = length(v$entrena),
    inicio_valida  = format(v$origen, "%Y-%m-%d"),
    fin_valida     = format(v$fin - 1, "%Y-%m-%d"),
    n_valida       = length(v$valida),
    # La tasa de la reserva no se calcula aquí: sus respuestas no se examinan antes de congelar el diseño.
    tasa_entrena   = round(mean(base_modelo$Y[v$entrena]), 4)
  )
}))
print(resumen_particiones)
write_csv(resumen_particiones, "output/tablas/particiones.csv")

saveRDS(
  list(
    ventanas = lapply(ventanas, function(v) list(
      origen = v$origen, fin = v$fin,
      entrena_key = base_modelo$unique_key[v$entrena],
      valida_key  = base_modelo$unique_key[v$valida]
    )),
    reserva = list(
      origen = final_reserva$origen, fin = final_reserva$fin,
      entrena_key = base_modelo$unique_key[final_reserva$entrena],
      valida_key  = base_modelo$unique_key[final_reserva$valida]
    )
  ),
  "output/particiones.rds"
)

# --- 4. Diagrama temporal -----------------------------------------------
diagrama <- bind_rows(lapply(seq_along(ventanas), function(i) {
  v <- ventanas[[i]]
  tibble(
    fila = paste0("Ventana ", i),
    tipo = c("Entrenamiento", "Separación (7 días)", "Validación"),
    ini  = c(as.POSIXct("2021-01-01", tz = TZ_NY), v$origen - HORIZONTE, v$origen),
    fin  = c(v$origen - HORIZONTE, v$origen, v$fin)
  )
}))
diagrama <- bind_rows(diagrama, tibble(
  fila = "Evaluación final",
  tipo = c("Entrenamiento", "Separación (7 días)", "Reserva (una evaluación)"),
  ini  = c(as.POSIXct("2021-01-01", tz = TZ_NY), inicio_reserva - HORIZONTE, inicio_reserva),
  fin  = c(inicio_reserva - HORIZONTE, inicio_reserva, final_reserva$fin)
)) |>
  mutate(fila = factor(fila, levels = rev(c(paste0("Ventana ", 1:3), "Evaluación final"))))

fig_diagrama <- ggplot(diagrama, aes(y = fila, yend = fila, x = ini, xend = fin, colour = tipo)) +
  geom_segment(linewidth = 6) +
  scale_colour_manual(values = c(
    "Entrenamiento" = "#3B6FB6", "Separación (7 días)" = "#111111",
    "Validación" = "#E08A1E", "Reserva (una evaluación)" = "#B23A48"
  )) +
  scale_x_datetime(date_breaks = "6 months", date_labels = "%b %Y") +
  labs(x = "Fecha de ingreso de la solicitud", y = NULL, colour = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")
ggsave("output/figuras/diagrama_temporal.png", fig_diagrama, width = 7, height = 2.6, dpi = 200)

# --- 5. Funciones comunes de evaluación ---------------------------------
# Se calculan a mano para aplicar exactamente la misma fórmula a todos los modelos.
# Pérdida logarítmica por fila (métrica principal). Menor es mejor. p se acota para
# evitar log(0) cuando un modelo predice exactamente 0 o 1.
log_loss_vec <- function(y, p) {
  p <- pmin(pmax(p, 1e-15), 1 - 1e-15)
  -(y * log(p) + (1 - y) * log(1 - p))
}
# AUC por rangos: probabilidad de que un caso Y = 1 reciba mayor p que uno Y = 0.
auc_vec <- function(y, p) {
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(rank(p)[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
metricas <- function(y, p) {
  tibble(
    n = length(y), prevalencia = mean(y),
    log_loss = mean(log_loss_vec(y, p)),
    brier = mean((y - p)^2),
    auc = if (length(unique(p)) > 1) auc_vec(y, p) else 0.5
  )
}
# Matriz de confusión y sus resúmenes: "positivo" significa predecir sin cierre a 7 días.
metricas_umbral <- function(y, p, umbral) {
  pos <- p >= umbral
  tp <- sum(pos & y == 1); fp <- sum(pos & y == 0)
  fn <- sum(!pos & y == 1); tn <- sum(!pos & y == 0)
  tibble(
    umbral = umbral, VP = tp, FP = fp, FN = fn, VN = tn,
    sensibilidad = tp / (tp + fn),
    especificidad = tn / (tn + fp),
    vpp = if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
  )
}
