# EYP3407 — Caso 08: Plazos de cierre de solicitudes NYC 311

## Integrantes
- Diego Barrios (@nickname1)
- Renato Bazaes [@RenatoBazaesS](https://github.com/RenatoBazaesS)
- Mauricio Campillay [@mauricio-campillay-mm](https://github.com/mauricio-campillay-mm)
- Bruno Zavala (@nickname4)

## Caso asignado
Caso 08 — NYC 311. Pregunta: al ingresar una solicitud de la agencia HPD con categoría PLUMBING entre 2021 y 2023,
¿cuál es la probabilidad de que siga sin cierre administrativo al cumplirse 7 días?

## Contexto y finalidad
Trabajo final de EYP3407. Estima, al ingreso de una solicitud de plomería a HPD, la
probabilidad de que siga sin cierre administrativo a los 7 días, para apoyar la
priorización del seguimiento. Es una evaluación retrospectiva con la copia entregada:
el cierre administrativo no equivale a resolución material y no se afirman efectos causales.


## Entorno
- Lenguaje: R 4.6.2 (recomendado; con otra versión `analisis.R` avisa y continúa).
- Quarto 1.11.9 y una distribución LaTeX (`quarto install tinytex`).
- Gestión de dependencias: `renv` 1.3.1; `renv.lock` fija 129 paquetes en
  Posit Package Manager con fecha 2026-11-06, con binarios para Windows y Linux.
- Paquetes principales usados:  `readr`, `dplyr`, `lubridate`, `tidymodels`,
  `ranger`, `xgboost`, `yardstick`, `probably`,
  `ggplot2`, `scales`, `quarto`

## Estructura del proyecto (por ahora)

```text
proyecto/
│
├── instalar.R                      # instala las versiones exactas de renv.lock
├── analisis.R                      # punto de entrada único (ejecuta y genera todo)
├── README.md
├── renv.lock                       # versiones exactas de paquetes
├── informe.qmd                     # fuente del informe (genera informe.pdf)
│
├── R/                              
│   ├── 00_entorno.R                # verifica entorno y datos; fija opciones deterministas
│   ├── 01_preparacion.R            # auditoría, construcción de Y, base analítica
│   ├── 02_particiones.R            # desarrollo/prueba, ventanas temporales
│   ├── 03_modelos.R                # referencia, M1, M2, M3
│   ├── 04_evaluacion.R             # métricas, comparación, incertidumbre
│   ├── 05_diagnostico.R            # sensibilidades y estabilidad en desarrollo
│   └── 06_reserva.R                # evaluación única 2023, incertidumbre, errores por subgrupo
│
├── datos/
│   ├── caso08_nyc311.zip           # paquete original sin editar
│   ├── datos.csv                   # extraído del zip
│   ├── diccionario.csv             # definiciones de variable
│   └── LEEME.txt                   # información de los datos
│
├── docs/
│   └── 00_definicion_problema.md
│
└── output/                         # se genera al ejecutar analisis.R
    ├── tablas/
    ├── figuras/
    └── sessionInfo.txt
```

## Datos
- Archivo original: `caso08_nyc311.zip` (incluido en `datos/`).
- Fuente: NYC Open Data, *311 Service Requests from 2020 to Present* (erm2-nwe9).
- Fecha de la copia: 12 de octubre de 2026 (según `datos/LEEME.txt`).
- Filtros de la copia: `agency = HPD`, `complaint_type = PLUMBING`,
  `created_date` entre 2021-01-01 y 2023-12-31.
- Contenido del zip: `datos.csv`, `diccionario.csv`, `LEEME.txt`.
- MD5 del zip: 42a7931a2a2b19fdfa04b73823c85903.
- Toda transformación a los archivos originales se hace en `R/01_preparacion.R`.

## Instalación
1. Instalar [R 4.6.2](https://cran.r-project.org/) y [Quarto](https://quarto.org/docs/get-started/).
2. Clonar el repositorio.
3. Desde la raíz del proyecto, instalar paquetes y LaTeX:
   ```bash
   Rscript --vanilla instalar.R
   quarto install tinytex
   ```

En Windows no se necesita Rtools y `datos.csv` se extrae solo. Si R no está en
el PATH, usar la ruta completa, por ejemplo
`"C:\Program Files\R\R-4.6.2\bin\Rscript.exe"`.

`R/00_entorno.R` comprueba versión de R, paquetes, datos, Quarto y LaTeX antes
de empezar, y fija el orden de texto, el generador aleatorio y los hilos de
`xgboost` para que el resultado no dependa del idioma o de los núcleos del equipo.
Entre sistemas operativos pueden aparecer diferencias numéricas mínimas.

## Ejecución
```r
Rscript --vanilla analisis.R
```
Este comando ejecuta preparación, particiones, ajuste, evaluación,
diagnóstico y la generación de `informe.pdf`, tablas y figuras.

## Reproducibilidad y costo
- Semilla fija: `set.seed(3407)` en `analisis.R`.
- Tiempo aproximado de ejecución: 19 min, con 4 hilos para `xgboost`.
- Sistema de referencia: Windows 11 x64, R 4.6.2, 16 GB de RAM.
- La sesión completa queda registrada en `output/sessionInfo.txt`.

## Prueba desde una copia limpia
- Fecha: 8 de noviembre de 2026.
- Comando utilizado: `Rscript --vanilla instalar.R` y `Rscript --vanilla analisis.R`.
- Resultado: ejecución completa en 19 min desde un clon limpio, con tablas de resultados
  idénticas a una corrida anterior.
- Sistema: Windows 11 x64, R 4.6.2, en el equipo de desarrollo.
- Prueba en el computador de otro integrante: <fecha, sistema, comando y resultado>.

## Aportes del equipo
- Diego Barrios: <aporte>.
- Renato Bazaes: <aporte>.
- Mauricio Campillay: <aporte>.
- Bruno Zavala: <aporte>.

## Declaración de uso de IA
- Herramienta y fecha: Claude Code (modelo Claude Opus 5.5), 8 de noviembre de 2026. <agregar otras herramientas usadas por el equipo>.
- Propósito: programación, depuración, entorno reproducible y borrador de secciones descriptivas y diapositivas.
- Partes afectadas: `analisis.R`, `instalar.R`, `R/00_entorno.R` a `R/06_reserva.R`, `informe.qmd`, `presentacion.qmd` y este archivo.
- Comprobaciones realizadas: ejecución completa desde un clon limpio. <agregar la revisión manual y verificación hecha por el equipo>.

## Referencias
- NYC Open Data. *311 Service Requests from 2020 to Present*. ID erm2-nwe9.
  https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2020-to-Present/erm2-nwe9
- Datos obtenidos de Canvas en curso EYP3407, "Proyecto Final: Caso 08" (12 de octubre de 2026).

