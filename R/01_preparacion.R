ruta_csv <- "datos/datos.csv"
if (!file.exists(ruta_csv)) {
  utils::unzip("datos/caso08_nyc311.zip", exdir = "datos")
}
datos <- readr::read_csv(ruta_csv, show_col_types = FALSE)
dic   <- readr::read_csv("datos/diccionario.csv", show_col_types = FALSE)