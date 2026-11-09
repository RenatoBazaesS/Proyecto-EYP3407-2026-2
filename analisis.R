# analisis.R — punto de entrada único
# Ejecutar desde la raíz: Rscript --vanilla analisis.R

# --vanilla omite .Rprofile: renv debe activarse explícitamente.
source("renv/activate.R")
source("R/00_entorno.R")

t0 <- Sys.time()
set.seed(3407)

dir.create("output/tablas",  recursive = TRUE, showWarnings = FALSE)
dir.create("output/figuras", recursive = TRUE, showWarnings = FALSE)

source("R/01_preparacion.R")
source("R/02_particiones.R")
source("R/03_modelos.R")
source("R/04_evaluacion.R")
source("R/05_diagnostico.R")
source("R/06_reserva.R")

writeLines(capture.output(sessionInfo()), "output/sessionInfo.txt")
tiempo_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
writeLines(sprintf("%.1f", tiempo_min), "output/tablas/tiempo_ejecucion_min.txt")

quarto::quarto_render("informe.qmd")
quarto::quarto_render("presentacion.qmd")
cat("Tiempo total:", format(Sys.time() - t0), "\n")