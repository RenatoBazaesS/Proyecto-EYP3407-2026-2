# Definición del problema — Caso 08 NYC 311

## Audiencia y decisión
- Audiencia: oficina de gestión de solicitudes de HPD y equipos de operaciones
  que priorizan casos de `PLUMBING`.
- Decisión que apoya: identificar, al ingreso de la solicitud, cuáles tienen
  mayor probabilidad de no cerrarse administrativamente en 7 días, para
  priorizar seguimiento.

## Población
Solicitudes de servicio (SR) dirigidas a HPD, con `complaint_type = PLUMBING`,
creadas entre 2021-01-01 y 2023-12-31 en la ciudad de Nueva York, según la
copia entregada (ver `datos/LEEME.txt`).

## Unidad de observación
Una solicitud única, identificada por `unique_key`.

## Respuesta y unidad de medida
`Y = 1` si no se registra cierre administrativo dentro de las primeras 168 horas
desde `created_date`; `Y = 0` si el cierre ocurre dentro de 168 horas.
Unidad: binaria. Horizonte: 7 días (168 h).

## Horizonte y disponibilidad de predictores
- Predicción emitida al ingreso de la solicitud (t = `created_date`).
- Sólo son admisibles atributos conocidos al ingreso: calendario del ingreso
  (día de semana, mes, año, hora), canal de ingreso, tipo de localización,
  borough, community_board, council_district, police_precinct, incident_zip,
  descriptor, facility_type.
- Historial de solicitudes previas puede usarse sólo si su ventana de 7 días
  ya terminó antes de t.
- Excluidos como predictores: closed_date, status, resolution_description,
  resolution_action_updated_date, due_date, unique_key y cualquier campo que
  revele el resultado o la duración.

## Naturaleza del análisis
- Retrospectivo, condicionado a que la solicitud fue creada y está en la copia.
- El cierre administrativo no equivale a resolución material del problema.
- Una asociación predictiva no demuestra causalidad.
- No se afirma rendimiento operativo en tiempo real: la copia fue descargada
  el 2026-10-12 y no reconstruye el estado exacto del sistema en el momento
  del ingreso de cada solicitud.