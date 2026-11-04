# analisis.R — punto de entrada único
# Ejecutar desde la raíz: Rscript --vanilla analisis.R

t0 <- Sys.time()
set.seed(3407)

dir.create("output/tablas",  recursive = TRUE, showWarnings = FALSE)
dir.create("output/figuras", recursive = TRUE, showWarnings = FALSE)

source("R/01_preparacion.R")
source("R/02_particiones.R")
source("R/03_modelos.R")
source("R/04_evaluacion.R")
source("R/05_diagnostico.R")

# Render del informe (se activa cuando exista informe.qmd)
# quarto::quarto_render("informe.qmd")

writeLines(capture.output(sessionInfo()), "output/sessionInfo.txt")
cat("Tiempo total:", format(Sys.time() - t0), "\n")