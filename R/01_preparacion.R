suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(tidyr)
  library(stringr)
  library(ggplot2)
})

ruta_csv <- "datos/datos.csv"
if (!file.exists(ruta_csv)) {
  utils::unzip("datos/caso08_nyc311.zip", exdir = "datos")
}
datos_raw <- readr::read_csv(ruta_csv, show_col_types = FALSE)
dic   <- readr::read_csv("datos/diccionario.csv", show_col_types = FALSE)
summary(datos_raw)
message("Filas leídas: ", nrow(datos_raw))
message("Columnas: ",   ncol(datos_raw))

# --- 2. Auditoría de clave ---------------------------------------------
stopifnot("unique_key no es única" = nrow(datos_raw) == n_distinct(datos_raw$unique_key))
auditoria_clave <- tibble(
  filas        = nrow(datos_raw),
  claves_unicas = n_distinct(datos_raw$unique_key),
  duplicados   = nrow(datos_raw) - n_distinct(datos_raw$unique_key)
)
message("Duplicados por unique_key: ", auditoria_clave$duplicados)

# No hay ID duplicados --> OK!

# --- 3. Parseo de fechas -----------------------------------------------
# NYC 311 entrega created_date/closed_date en hora local de Nueva York.
# read_csv ya las entrega como POSIXct (rotuladas UTC), por lo que basta
# reasignar la zona horaria conservando la hora de reloj. Volver a pasarlas por
# ymd_hms() las convierte a texto y pierde las fechas exactamente a medianoche.
# Las horas inexistentes o repetidas por cambio de hora se resuelven de forma fija.
datos <- datos_raw |>
  mutate(
    created_date = force_tz(created_date, "America/New_York", roll_dst = c("post", "pre")),
    closed_date  = force_tz(closed_date,  "America/New_York", roll_dst = c("post", "pre"))
  )

n_created_na <- sum(is.na(datos$created_date))
message("created_date no parseable: ", n_created_na)

# Ninguna fecha presente en el archivo puede perderse al asignar la zona horaria.
stopifnot(
  "se perdió created_date al parsear" = sum(is.na(datos$created_date)) == sum(is.na(datos_raw$created_date)),
  "se perdió closed_date al parsear"  = sum(is.na(datos$closed_date))  == sum(is.na(datos_raw$closed_date))
)

# --- 4. Construcción de la respuesta Y ---------------------------------
# La escala será en horas. Entonces, 7 dias = 168 horas. 
# Y = 1, si no cerró en menos de 168 horas.
# Y = 0, si cerró antes de 168 horas.

datos <- datos |>
  mutate(
    horas_cierre = as.numeric(difftime(closed_date, created_date, units = "hours")),
    Y = case_when(
      is.na(created_date)              ~ NA_integer_,
      is.na(closed_date)               ~ 1L,           # sin cierre registrado al corte
      horas_cierre < 0                 ~ NA_integer_,  # duración negativa → auditar
      horas_cierre <= 168              ~ 0L,
      TRUE                             ~ 1L
    )
  )

# Auditoría de Y
auditoria_Y <- datos |>
  mutate(caso = case_when(
    is.na(created_date) ~ "created_date inválido",
    is.na(closed_date)  ~ "sin cierre registrado",
    horas_cierre < 0    ~ "duración negativa",
    horas_cierre <= 168 ~ "cerrada en <= 168 h",
    TRUE                ~ "cerrada en > 168 h"
  )) |>
  count(caso) |>
  mutate(pct = round(100 * n / sum(n), 2)) |>
  arrange(desc(n))
print(auditoria_Y)

# --- 5. Reglas de exclusión y base analítica ----------------------------
# Se excluyen:
#   - created_date no parseable
#   - duraciones negativas (closed_date < created_date)
# No se excluyen solicitudes sin cierre: son el grupo Y = 1.
base <- datos |>
  filter(
    !is.na(created_date),
    is.na(closed_date) | horas_cierre >= 0
  ) |>
  filter(!is.na(Y))

message("Base analítica: ", nrow(base), " filas (", round(100 * nrow(base) / nrow(datos), 2), "% de las leídas)")

# --- 6. Tabla de construcción de la muestra ----------------------------
construccion <- tibble(
  paso = c(
    "Filas leídas del CSV",
    "created_date parseable",
    "Duraciones no negativas",
    "Con Y observada (base analítica)"
  ),
  n = c(
    nrow(datos),
    sum(!is.na(datos$created_date)),
    sum(!is.na(datos$created_date) & (is.na(datos$closed_date) | datos$horas_cierre >= 0)),
    nrow(base)
  )
) |>
  mutate(pct_del_total = round(100 * n / nrow(datos), 2))
print(construccion)

# Calidad de fechas, informada por separado como pide la ficha del caso.
fecha_extraccion <- as.POSIXct("2026-10-12", tz = "America/New_York")
calidad_fechas <- tibble(
  control = c(
    "created_date ausente o no interpretable (excluida)",
    "Cierre anterior a la creación (excluida)",
    "Sin cierre registrado (se conserva, Y = 1)",
    "Cierre exactamente a medianoche (se conserva)",
    "Cierre más de 365 días después de la creación (se conserva)",
    "Menos de 7 días de seguimiento al extraer (excluiría)"
  ),
  n = c(
    sum(is.na(datos$created_date)),
    sum(datos$horas_cierre < 0, na.rm = TRUE),
    sum(is.na(datos$closed_date)),
    sum(format(datos_raw$closed_date, "%H:%M:%S") == "00:00:00", na.rm = TRUE),
    sum(datos$horas_cierre > 365 * 24, na.rm = TRUE),
    sum(datos$created_date + 168 * 3600 > fecha_extraccion, na.rm = TRUE)
  )
)
print(calidad_fechas)

# --- 7. Tabla de variables: admisibles vs excluidas --------------------
# Esto basado en el diccionario. Qué servirá como predictor y qué no.
predictores <- tribble(
  ~variable,                        ~interpretacion,                  ~tipo,        ~disponibilidad,        ~decision,                  ~razon,
  "unique_key",                     "ID de la solicitud",             "texto",      "al ingreso",           "excluida (identificador)", "no es predictor",
  "closed_date",                    "fecha de cierre",                "fecha",      "posterior",            "excluida (resultado)",     "define Y",
  "status",                         "estado final",                   "categórica", "posterior",            "excluida (resultado)",     "revela el resultado",
  "resolution_description",         "texto de resolución",            "texto",      "posterior",            "excluida (resultado)",     "describe el cierre",
  "resolution_action_updated_date", "última actualización",           "fecha",      "posterior",            "excluida (resultado)",     "posterior al ingreso",
  "due_date",                       "fecha comprometida",             "fecha",      "incierta",             "excluida",                 "SLA interno; sin registro de cuándo se fija",
  "created_date",                   "fecha de ingreso",               "fecha",      "al ingreso",           "incluida (derivadas)",     "mes, día de semana y hora; año excluido porque 2023 no se observa en entrenamiento",
  "open_data_channel_type",         "canal de ingreso",               "categórica", "al ingreso",           "incluida",                 "atributo de ingreso",
  "agency",                         "agencia",                        "categórica", "al ingreso",           "excluida (constante)",     "HPD por construcción",
  "complaint_type",                 "tipo de problema",               "categórica", "al ingreso",           "excluida (constante)",     "PLUMBING por construcción",
  "descriptor",                     "detalle del problema",           "categórica", "al ingreso (supuesto)", "incluida",                "se supone estable tras el ingreso",
  "descriptor_2",                   "detalle adicional",              "categórica", "al ingreso (supuesto)", "incluida",                "se supone estable tras el ingreso; categorías raras agrupadas",
  "location_type",                  "tipo de localización",           "categórica", "al ingreso",           "excluida (constante)",     "un solo nivel en la copia",
  "facility_type",                  "tipo de instalación",            "categórica", "al ingreso",           "excluida (vacía)",         "100% faltante",
  "borough",                        "condado",                        "categórica", "al ingreso (supuesto)", "incluida",                "ubicación agregada",
  "community_board",                "distrito comunitario",           "categórica", "al ingreso (supuesto)", "incluida",                "ubicación agregada; categorías raras agrupadas",
  "council_district",               "distrito municipal",             "categórica", "al ingreso (supuesto)", "incluida",                "ubicación agregada; categorías raras agrupadas",
  "police_precinct",                "precinto policial",              "categórica", "al ingreso (supuesto)", "incluida",                "ubicación agregada; categorías raras agrupadas",
  "incident_zip",                   "código postal",                  "categórica", "al ingreso (supuesto)", "incluida",                "ubicación agregada; categorías raras agrupadas",
  "incident_address",               "dirección",                      "texto",      "al ingreso",           "excluida (identificador)", "no se usa ni publica",
  "street_name",                    "calle",                          "texto",      "al ingreso",           "excluida (identificador)", "no se usa ni publica",
  "bbl",                            "identificador de inmueble",      "texto",      "al ingreso",           "solo agrupación",          "historial de volumen, sensibilidad y bootstrap",
  "latitude",                       "latitud",                        "numérica",   "al ingreso",           "excluida",                 "se usa ubicación agregada",
  "longitude",                      "longitud",                       "numérica",   "al ingreso",           "excluida",                 "se usa ubicación agregada"
)
print(predictores)

# --- 8. Calidad: faltantes y cardinalidad ------------------------------
calidad <- base |>
  summarise(across(
    c(descriptor, location_type, facility_type, borough, community_board,
      council_district, police_precinct, incident_zip, open_data_channel_type),
    ~ mean(is.na(.x))
  )) |>
  pivot_longer(everything(), names_to = "variable", values_to = "pct_na") |>
  mutate(pct_na = round(100 * pct_na, 2)) |>
  arrange(desc(pct_na))
print(calidad)

# Realmente la variable de facility_type es 100% NA. Inútil.
# council_district (23) e incident_zip (23) poseen un 0.01% de NA. Veremos que hacer con eso.
# Podrían estar correlacionados: si no se sabe el distrito, implica que tampoco se sepa su codigo postal.

cardinalidad <- base |>
  summarise(across(
    c(descriptor, location_type, facility_type, borough, community_board,
      council_district, police_precinct, incident_zip, open_data_channel_type),
    n_distinct
  )) |>
  pivot_longer(everything(), names_to = "variable", values_to = "n_niveles") |>
  arrange(desc(n_niveles))
print(cardinalidad)

# Varios codigos postal distintos (183), y otros más. 

# --- 9. Descripción de la muestra --------------------------------------
descripcion <- tibble(
  metrica = c(
    "n_solicitudes",
    "n_bbl_distintos",
    "n_zip_distintos",
    "fecha_min",
    "fecha_max",
    "prevalencia_Y",
    "pct_Y_sin_cierre"
  ),
  valor = c(
    as.character(nrow(base)),
    as.character(n_distinct(base$bbl, na.rm = TRUE)),
    as.character(n_distinct(base$incident_zip, na.rm = TRUE)),
    as.character(min(base$created_date, na.rm = TRUE)),
    as.character(max(base$created_date, na.rm = TRUE)),
    as.character(round(mean(base$Y), 4)),
    as.character(round(100 * mean(is.na(base$closed_date)), 2))
  )
)
print(descripcion)

# Cobertura por año y borough
cobertura <- base |>
  mutate(anio = year(created_date)) |>
  count(anio, borough) |>
  tidyr::pivot_wider(names_from = borough, values_from = n, values_fill = 0)
print(cobertura)

# --- 10. Guardar salidas -----------------------------------------------
write_csv(auditoria_clave, "output/tablas/auditoria_clave.csv")
write_csv(auditoria_Y,     "output/tablas/auditoria_Y.csv")
write_csv(construccion,    "output/tablas/construccion_muestra.csv")
write_csv(predictores,     "output/tablas/variables.csv")
write_csv(calidad,         "output/tablas/calidad_na.csv")
write_csv(cardinalidad,    "output/tablas/cardinalidad.csv")
write_csv(descripcion,     "output/tablas/descripcion.csv")
write_csv(cobertura,       "output/tablas/cobertura_anio_borough.csv")
write_csv(calidad_fechas,  "output/tablas/calidad_fechas.csv")

# Diagrama de construcción de la muestra, con los conteos calculados arriba.
fmt_n <- function(x) format(x, big.mark = ".", decimal.mark = ",", trim = TRUE)
n_dev <- sum(year(base$created_date) < 2023)
n_res <- sum(year(base$created_date) == 2023)
cajas <- tibble(
  x = c(0, 0, 0, -1.25, 1.25),
  y = c(3, 2, 1, 0, 0),
  texto = c(
    paste0("Filas en datos.csv\nn = ", fmt_n(nrow(datos))),
    paste0("Fecha de creación válida y duración no negativa\nexcluidas: ",
           fmt_n(nrow(datos) - nrow(base))),
    paste0("Base analítica\nn = ", fmt_n(nrow(base)), " · ",
           fmt_n(sum(base$Y == 1)), " sin cierre a 7 días (Y = 1)"),
    paste0("Desarrollo 2021-2022\nn = ", fmt_n(n_dev)),
    paste0("Reserva 2023\nn = ", fmt_n(n_res))
  )
)
flechas <- tibble(x = c(0, 0, 0, 0), xend = c(0, 0, -1.25, 1.25),
                  y = c(2.72, 1.72, 0.72, 0.72), yend = c(2.28, 1.28, 0.28, 0.28))
fig_muestra <- ggplot() +
  geom_segment(data = flechas, aes(x, y, xend = xend, yend = yend),
               arrow = arrow(length = unit(2, "mm")), colour = "grey40") +
  geom_label(data = cajas, aes(x, y, label = texto), size = 3, label.size = 0.3) +
  coord_cartesian(xlim = c(-2.4, 2.4), ylim = c(-0.4, 3.4)) +
  theme_void()
ggsave("output/figuras/diagrama_muestra.png", fig_muestra, width = 6.5, height = 3.2, dpi = 200)

saveRDS(base, "output/datos_auditados.rds")
message("Preparación lista: ", nrow(base), " filas en output/datos_auditados.rds")

