# instalar.R — instala las versiones exactas de renv.lock
# Ejecutar una vez desde la raíz del proyecto: Rscript --vanilla instalar.R

source("renv/activate.R")
renv::restore(prompt = FALSE)

if (is.null(quarto::quarto_path())) {
  message("Falta Quarto: https://quarto.org/docs/get-started/")
} else if (!(tinytex::is_tinytex() || nzchar(Sys.which("lualatex")) || nzchar(Sys.which("xelatex")))) {
  message("Falta LaTeX. Ejecute: quarto install tinytex")
}
message("Instalación terminada. Ahora ejecute: Rscript --vanilla analisis.R")
