# EYP3407 — Caso 08: Plazos de cierre de solicitudes NYC 311

## Integrantes
- Diego Barrios (@nickname1)
- Renato Bazaes [@RenatoBazaesS](https://github.com/RenatoBazaesS)
- Mauricio Campillay (@nickname3)
- Bruno Zavala (@nickname4)

## Caso asignado
Caso 08 — NYC 311. Pregunta: al ingresar una solicitud de la agencia HPD con categoría PLUMBING entre 2021 y 2023,
¿cuál es la probabilidad de que siga sin cierre administrativo al cumplirse 7 días?

## Contexto y finalidad


## Entorno
- Lenguaje: R versión 4.5.0.
- Gestión de dependencias: `renv` versión 1.3.1 (ver `renv.lock`).
- Paquetes principales usados:  `readr`, `dplyr`, `lubridate`, `tidymodels`,
  `ranger`, `xgboost`, `yardstick`, `probably`,
  `ggplot2`, `scales`, `quarto`

## Estructura del proyecto (por ahora)

```text
proyecto/
│
├── analisis.R                      # punto de entrada único (ejecuta y genera todo)
├── README.md
├── renv.lock                       # versiones exactas de paquetes
├── informe.qmd                     # fuente del informe (genera informe.pdf)
│
├── R/                              
│   ├── 01_preparacion.R            # auditoría, construcción de Y, base analítica
│   ├── 02_particiones.R            # desarrollo/prueba, ventanas temporales
│   ├── 03_modelos.R                # referencia, M1, M2, M3
│   ├── 04_evaluacion.R             # métricas, comparación, incertidumbre
│   └── 05_diagnostico.R            # errores por subgrupo, sensibilidades
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
1. Clonar el repositorio.
2. Abrir R en la raíz del proyecto.
3. Ejecutar `renv::restore()`

## Ejecución
```r
Rscript --vanilla analisis.R
```
Este comando ejecuta preparación, particiones, ajuste, evaluación,
diagnóstico y la generación de `informe.pdf`, tablas y figuras.

## Reproducibilidad y costo
- Semilla fija: `set.seed(3407)` en `analisis.R`.
- Tiempo aproximado de ejecución: <XX> min.
- Sistema de referencia: <Windows, R 4.5.0>.
- La sesión completa queda registrada en `output/sessionInfo.txt`.

## Prueba desde una copia limpia
- Fecha:
- Comando utilizado: `Rscript --vanilla analisis.R`
- Resultado:
- Sistema:

## Aportes del equipo
- Diego Barrios: <aporte>.
- Renato Bazaes: <aporte>.
- Mauricio Campillay: <aporte>.
- Bruno Zavala: <aporte>.

## Declaración de uso de IA
- Herramienta y fecha: <XX>.
- Propósito: <XX>.
- Partes afectadas: <archivos o secciones>.
- Comprobaciones realizadas: <ejecución completa, revisión manual, verificación de resultados>.

## Referencias
- NYC Open Data. *311 Service Requests from 2020 to Present*. ID erm2-nwe9.
  https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2020-to-Present/erm2-nwe9
- Datos obtenidos de Canvas en curso EYP3407, "Proyecto Final: Caso 08" (12 de octubre de 2026).

