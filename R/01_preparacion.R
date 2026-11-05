suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(tidyr)
  library(stringr)
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
datos <- datos_raw |>
  mutate(
    created_date = ymd_hms(created_date, tz = "America/New_York"),
    closed_date  = ymd_hms(closed_date,  tz = "America/New_York")
  )

n_created_na <- sum(is.na(datos$created_date))
message("created_date no parseable: ", n_created_na)

# Hay un NA! Lo vamos a eliminar ya que es solamente un dato.

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

# Y = 1; n = 99352 + 300 (58.2% + 0.18% = 58.38%)
# Y = 0, n = 71155 (41.7%)

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

# En resumen, solamente se eliminó el NA que existía.

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

# --- 7. Tabla de variables: admisibles vs excluidas --------------------
# Esto basado en el diccionario. Qué servirá como predictor y qué no.
predictores <- tribble(
  ~variable,                        ~rol,                 ~razon,
  "unique_key",                     "identificador",      "ID único; no es predictor",
  "closed_date",                    "excluida",           "define Y",
  "status",                         "excluida",           "estado final, revela resultado",
  "resolution_description",         "excluida",           "describe la resolución",
  "resolution_action_updated_date", "excluida",           "actualización posterior al ingreso",
  "due_date",                       "excluida",           "SLA interno que puede depender del resultado",
  "created_date",                   "predictor (calendario)", "día de semana, mes, año, hora",
  "open_data_channel_type",         "predictor",          "canal de ingreso",
  "agency",                         "constante",          "HPD por construcción",
  "complaint_type",                 "constante",          "PLUMBING por construcción",
  "descriptor",                     "predictor",          "detalle del problema (agrupar raras)",
  "location_type",                  "predictor",          "tipo de localización (agrupar raras)",
  "facility_type",                  "predictor",          "tipo de facility si está disponible",
  "borough",                        "predictor",          "borough reportado",
  "community_board",                "predictor",          "distrito comunitario",
  "council_district",               "predictor",          "distrito municipal",
  "police_precinct",                "predictor",          "precinto policial",
  "incident_zip",                   "predictor",          "código postal (agrupar raras)",
  "incident_address",               "solo agrupación",    "no usar como predictor",
  "street_name",                    "solo agrupación",    "no usar como predictor",
  "bbl",                            "solo agrupación",    "identificador de edificio; útil para historial o bootstrap",
  "latitude",                       "solo agrupación",    "usar sólo para agrupar o mapas",
  "longitude",                      "solo agrupación",    "usar sólo para agrupar o mapas"
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

saveRDS(base, "output/datos_auditados.rds")
message("Preparación lista: ", nrow(base), " filas en output/datos_auditados.rds")

