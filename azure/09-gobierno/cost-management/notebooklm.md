# NotebookLM · Azure · Cost Management

**Fuentes a subir:** todos los `.md` de esta carpeta, los archivos de `ejemplos/` (Terraform, CLI, JSON y KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Microsoft Cost Management de Azure, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es Cost Management y qué problema resuelve; la analogía del tablero de gastos de la casa; el diagrama del flujo de datos hasta presupuestos, alertas, exportaciones y análisis. Qué NO hace: no frena el consumo por sí mismo.
2. Cómo funciona por dentro: de dónde salen los datos y cuándo están disponibles (8 a 24 horas; hasta 48 en suscripciones nuevas), los alcances (grupo de administración, suscripción, grupo de recursos), tipos de contrato y diferencias, costo real frente a amortizado, monedas.
3. Presupuestos: umbrales reales y pronosticados, límites de cinco umbrales y cinco destinatarios, evaluación cada 24 horas, filtros por etiqueta o dimensión, grupos de acciones (solo en suscripción y grupo de recursos), la trampa de az consumption budget create sin notificaciones y los presupuestos creados con PowerShell que no envían avisos.
4. Alertas de anomalías: modelo de 60 días, ejecución 36 horas después del cierre del día, límites por suscripción, dependencia del acceso del creador. Diferencia entre presupuesto (acumulado) y anomalía (forma del gasto diario).
5. Exportaciones: tipos (real, amortizado, FOCUS, hoja de precios), CSV y Parquet, particionado y manifest.json, identidad administrada con Storage Blob Data Contributor, firewall con servicios de confianza y mismo tenant, versión de API y comportamiento de los primeros cinco días del mes.
6. Etiquetas y FinOps: etiquetas obligatorias impuestas con Azure Policy (Audit y luego Deny, valores permitidos), herencia de etiquetas en Cost Management, reglas de asignación de costos, consultas de cobertura y de recursos huérfanos con Resource Graph.
7. Seguridad y roles: Reader, Cost Management Reader, Contributor y Cost Management Contributor; la tabla de permisos por plano; identidades separadas para consultar, crear presupuestos y apagar recursos.
8. Los 12 casos reales como historias con su lección: la factura que nadie esperaba, el presupuesto que nunca avisó, creer que el presupuesto frena el gasto, el 30 % sin dueño, prod y Prod y produccion, el presupuesto de empresa sin acciones, la anomalía de la madrugada, el recurso ya apagado que sigue alertando, el panel de BI roto por el particionado, la exportación que no podía escribir, la alerta que se apagó sola y los mil dólares en discos sueltos.
9. Código Java: los dos paquetes (costmanagement y consumption) y por qué son dos; leer resultados por nombre de columna y la fecha AAAAMMDD; la caché; consultas por etiqueta, diaria por grupo de recursos y la proyección de fin de mes; el detalle del alcance sin barra inicial; el manejo de nextLink; presupuestos como código con validaciones y auditoría; el evaluador de nivel de gasto; la cobertura de etiquetas; el freno de laboratorios con webhook seguro, política acotada, simulacro, idempotencia y VM desasignadas; la métrica en Micrometer; Spring MVC con 429 y Retry-After; WebFlux con Mono.zip; Quarkus imperativo y reactivo con Mutiny; las pruebas.
10. Ejemplos de Terraform (grupo de acciones, presupuestos por suscripción, grupo de recursos y grupo de administración, alerta de anomalías y exportación diaria), CLI con az rest, cuerpos JSON de consultas y consultas KQL; qué hacer y qué NO hacer; costos y límites.
11. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
