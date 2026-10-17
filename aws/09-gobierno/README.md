# AWS · 09 Gobierno

Cuando la nube crece, la pregunta deja de ser «¿cómo creo esto?» y pasa a ser **«¿quién puede hacer qué, qué se salió de la norma, quién hizo qué y cuánto cuesta?»**. Este capítulo reúne las cuatro piezas de gobierno de AWS. Cada una responde una pregunta distinta, y las cuatro se **apoyan entre sí**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Organizations y SCP](organizations-scp/README.md) | ¿Qué está **permitido** hacer en cada cuenta, pase lo que pase? | El reglamento del edificio que ni el administrador de un piso puede saltarse | Cuentas por entorno y producto, límites preventivos (regiones, protección de la auditoría, IMDSv2) |
| [Config (reglas)](config-reglas/README.md) | ¿Qué recursos **incumplen** la norma ahora mismo? | El inspector que recorre el edificio con una lista de verificación | Cumplimiento continuo, historial de configuración, remediación |
| [CloudTrail](cloudtrail-auditoria/README.md) | ¿**Quién** hizo qué, cuándo y desde dónde? | El libro de visitas con cámara | Auditoría, investigación de incidentes, alarmas de seguridad |
| [Budgets y Cost Explorer](budgets-costos/README.md) | ¿**Cuánto** cuesta, de quién es y qué se salió de lo normal? | El tablero de gastos de la casa | Presupuestos con aviso, reparto por equipo, anomalías de costo |

> **Prevenir, detectar, investigar, controlar el costo.** SCP *previene*, Config *detecta* lo que se escapó, CloudTrail *explica* quién lo hizo, Budgets *avisa* de lo que cuesta. Ninguna reemplaza a las otras.

## Árbol de decisión: «quiero que…»

```
¿Quiero que NADIE (ni un administrador de la cuenta) pueda hacer X?
   └─ SCP en Organizations (techo de permisos; no otorga nada)

¿Quiero saber qué recursos YA existentes incumplen una regla (etiquetas, cifrado, acceso público)?
   └─ Config: reglas administradas o propias; remediación automática solo donde es seguro

¿Quiero saber QUIÉN borró o cambió algo, o detectar un uso sospechoso?
   └─ CloudTrail (traza multirregión a un bucket de otra cuenta) + alarmas

¿Quiero avisar cuando el gasto se acerca a un límite o se dispara de forma rara?
   └─ Budgets (real y pronosticado) + Cost Anomaly Detection

¿Quiero repartir la factura entre equipos?
   └─ Etiquetas de asignación de costos (activadas) + Cost Explorer / Data Exports

¿Quiero impedir que alguien APAGUE la auditoría?
   └─ SCP que niega StopLogging/DeleteTrail y cambios en Config + traza de organización

¿Quiero bloquear la creación de recursos cuando un sandbox se pasa de presupuesto?
   └─ Acción de presupuesto (aplica una política IAM/SCP), con aprobación manual al inicio

¿Quiero una cuenta nueva con todo lo anterior ya puesto?
   └─ Landing zone: cuenta creada con Organizations + SCP heredadas + traza + Config + presupuesto (capítulos 10 y 11)
```

## Comparativa

| Característica | Organizations / SCP | Config | CloudTrail | Budgets / Cost Explorer |
|---|---|---|---|---|
| **Momento** | Antes (preventivo) | Después de que existe el recurso (detectivo) | Cuando ocurre la llamada (registro) | Con el uso (con retraso de horas) |
| **Qué mira** | Permisos de las cuentas | Configuración de los recursos | Llamadas a la API | Costos y uso |
| **¿Bloquea?** | Sí | No (puede remediar) | No | No (las acciones pueden frenar) |
| **Alcance** | Árbol de la organización | Cuenta y región (con agregador) | Cuenta/organización; multirregión | Cuenta de pago y cuentas miembro |
| **Historial** | — | Línea de tiempo de configuración | 90 días (historial) o ilimitado (traza/Lake) | ~13 meses (Cost Explorer); más con exportaciones |
| **Quién lo administra** | Cuenta de administración | Equipo de plataforma/seguridad | Seguridad (cuenta de registros aparte) | Finanzas + plataforma |
| **Error típico** | Bloquearse a sí mismo (sin rol de emergencia) | Reglas ruidosas sin dueño | Traza que alguien pudo apagar | Aviso solo al 100 % real |
| **Costo base** | Gratis | Por elemento de configuración y evaluaciones | Eventos de datos, copias extra, Lake | Explorer gratis; API por solicitud |

## La receta ModaLima (cómo se ve junto)

| Necesidad | Pieza | Por qué |
|---|---|---|
| Cuentas por entorno (`prod`, `dev`, `sandbox`) y una de registros | **Organizations** con UO | Aislamiento y herencia de reglas |
| «Solo `us-east-1` y `sa-east-1`» | **SCP** de regiones con NotAction para servicios globales y rol de emergencia | Límite preventivo sin romper IAM/Organizations |
| Nadie apaga la auditoría | **SCP** sobre `StopLogging`, `DeleteTrail`, Config | Quien vigila no apaga la cámara |
| Recursos sin `equipo` ni `entorno` | **Config** (regla de etiquetas con parámetros) | Detecta y alimenta el reparto de costos |
| «¿Quién abrió ese puerto?» | **CloudTrail** + Athena | Evidencia con 90+ días |
| Inicio de sesión sin MFA, raíz, ráfagas de `AccessDenied` | **CloudTrail** → CloudWatch Logs → alarmas + detector en Java | Aviso en minutos |
| El sandbox no pasa de 300 USD | **Budgets** + acción que bloquea creación al 100 % | Freno controlado |
| Reparto por equipo y «sin etiqueta» | **Etiquetas activadas** + Cost Explorer | Showback honesto |
| Picos de costo por bucles o reintentos | **Cost Anomaly Detection** inmediata por SNS | Cuatro días de factura evitados |

## Orden recomendado de adopción

1. **Organizations** y cuentas separadas por entorno (y una cuenta de registros). Habilita acceso confiable para los servicios que usarás.
2. **CloudTrail** de organización hacia la cuenta de registros, con validación y KMS, y alarmas para raíz, MFA y cambios de la traza.
3. **SCP mínimas**: proteger la auditoría, restringir regiones, sin usuario raíz, IMDSv2. Pruébalas primero en una UO de pruebas.
4. **Budgets**: total y por equipo, con aviso pronosticado + real; **etiquetas activadas**; Cost Anomaly Detection.
5. **Config**: un paquete pequeño de reglas con dueño (etiquetas, cifrado, acceso público); remediación solo donde es segura.
6. **Todo como código** (capítulo 10): cuentas, políticas, reglas, trazas y presupuestos versionados y revisados.
7. **Landing zone** repetible para cada cuenta nueva (capítulo 11).

## Reglas transversales

- **Prevenir > detectar > llorar.** Lo que puedas impedir con una SCP, no lo dejes a una alarma.
- **Rol de emergencia (*break-glass*)** excluido de las SCP restrictivas, auditado y con MFA.
- **La auditoría vive en otra cuenta** y nadie de las aplicaciones puede borrarla.
- **Cada regla de Config tiene un dueño** y una acción esperada; sin dueño, es ruido.
- **Avisos pronosticados y reales**, por correo **y** SNS; destinos que alguien automatiza.
- **Etiquetas normalizadas y activadas** (`equipo`, `entorno`, `producto`); «sin etiqueta» es un indicador visible.
- **Cachea la API de costos**: cada solicitud tiene costo.
- **Prueba en una UO o cuenta de pruebas** antes de aplicar una SCP o una acción de presupuesto a producción.
- **Servicios globales desde `us-east-1`** (Organizations, Budgets, Cost Explorer).
- **Gobierno como código**: nada de cambios manuales sin traza.

## Java en gobierno: qué construye cada `uso-en-java.md`

Mismo molde de siempre: **un núcleo puro** (se prueba sin red), **un envoltorio del SDK** y los mismos casos en Spring MVC, WebFlux, Quarkus imperativo y Mutiny.

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Organizations y SCP | Validador de SCP (tamaño, estructura, errores típicos), generador de la SCP de regiones, árbol de la organización, creación/adjunto idempotentes | Núcleo puro + `PoliticaInvalida` antes de llamar a AWS |
| Config | Evaluador de etiquetas con parámetros, manejo de eventos con configuración completa u omitida, reporte por lotes con reintento de fallidas, resumen de cumplimiento | Lotes ≤ 100 con reintento por elemento |
| CloudTrail | Lector de archivos de la traza (también `.gz`), detector de raíz, MFA, cambios sensibles y ráfagas de `AccessDenied`; búsqueda con `LookupEvents` | Tolerancia a campos ausentes + ventana deslizante |
| Budgets y Costos | Proyección de fin de mes, reparto por etiqueta con «sin etiqueta», detector de picos, validador de avisos, consulta con caché | `BigDecimal` + caché de la API de pago por solicitud |

Reglas comunes: servicios globales con `Region.US_EAST_1`; en reactivo, los paginadores asíncronos se convierten con `Flux.from` / `Multi.createFrom().publisher(FlowAdapters…)`; los clientes se cierran ordenadamente (`destroyMethod`, `@Disposes`); credenciales por la cadena por defecto.

## Cómo se relaciona con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): cuentas, regiones, cuotas y facturación.
- [Red](../01-red/README.md): Flow Logs y reglas de red que Config y CloudTrail vigilan.
- [IAM](../02-iam/README.md): las SCP son el techo; IAM otorga dentro del techo.
- [Secretos](../03-secretos/README.md): KMS para la traza y el bucket de evidencia.
- [Compute](../04-compute/README.md): IMDSv2 y exigencias sobre instancias (SCP y Config).
- [Storage](../06-storage/README.md): el bucket de la traza, acceso público y bloqueo de objetos.
- [Mensajería](../07-mensajeria/README.md): SNS y EventBridge reciben los avisos de Config, CloudTrail y Budgets.
- [Datos](../08-datos/README.md): cifrado y acceso público de bases de datos como reglas de cumplimiento.
- [Terraform en AWS](../10-terraform/README.md): todo lo anterior como código y en una landing zone.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON, SQL), troubleshooting, repaso y prompt de NotebookLM.
