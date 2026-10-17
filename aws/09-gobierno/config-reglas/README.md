# AWS · Gobierno · AWS Config (configuración, cumplimiento y reglas)

**AWS Config registra cómo está configurado cada recurso de tu cuenta a lo largo del tiempo y evalúa, continuamente, si cumple las reglas que tú defines** («todo bucket cifrado», «toda instancia con la etiqueta `centro-costo`»). Responde a «¿cómo estaba esto el martes?» y «¿qué recursos hoy incumplen?». Puede, además, corregirlos.

## 1. Qué es

**Analogía:** el **inspector de obra con bitácora**. Toma una foto de cada recurso cada vez que cambia (historial) y compara cada foto con una lista de verificación (las reglas). Anota los incumplimientos y, si lo autorizas, manda a un operario a corregir lo corregible (remediación).

```
 Recursos de la cuenta           Config                               Salidas
 ┌────────────────────┐   ┌───────────────────────────┐   ┌───────────────────────────────┐
 │ EC2, S3, RDS, IAM… │──►│ Registrador (recorder)    │──►│ Historial y fotos en S3        │
 └────────────────────┘   │  elemento de configuración│   └───────────────────────────────┘
                          │           │               │   ┌───────────────────────────────┐
                          │           ▼               │──►│ Cumplimiento por regla/recurso │
                          │  Reglas (managed/Lambda/  │   └───────────────────────────────┘
                          │  Guard) → evaluación      │   ┌───────────────────────────────┐
                          └───────────────────────────┘──►│ EventBridge → SNS / tickets /  │
                                                          │ Remediación (SSM Automation)   │
                                                          └───────────────────────────────┘
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Registrador (*configuration recorder*)** | Qué recursos se graban (todos o tipos elegidos) y con qué frecuencia (continua o diaria) |
| **Elemento de configuración (CI)** | La «foto»: tipo, id, atributos, relaciones, etiquetas, hora de captura y estado (`OK`, `ResourceDeleted`…) |
| **Canal de entrega** | Dónde se guarda el historial: un bucket de S3 (obligatorio) y, opcionalmente, un tópico SNS |
| **Regla** | Una comprobación sobre recursos: **administrada** (cientos ya hechas), **personalizada con Lambda** o **de política (Guard)** |
| **Disparo** | Por **cambio de configuración** (con alcance por tipo o etiqueta), **periódico** (cada 1–24 h) o ambos |
| **Resultado** | `COMPLIANT`, `NON_COMPLIANT`, `NOT_APPLICABLE`, `INSUFFICIENT_DATA`; con una anotación breve (≤ 256 caracteres) |
| **Remediación** | Acción asociada a una regla (documento de SSM Automation), manual o automática, con reintentos |
| **Paquete de conformidad** | Conjunto de reglas y remediaciones como plantilla, desplegable en toda la organización |
| **Agregador** | Vista de cumplimiento de varias cuentas y regiones en una sola |
| **Consulta avanzada** | SQL sobre el inventario actual (`SELECT … WHERE resourceType = …`) |
| **Línea de tiempo del recurso** | Historial de cambios de un recurso concreto |
| **Notificaciones** | Cambios de cumplimiento y de configuración llegan a EventBridge/SNS |
| **Costo** | Se paga por elementos de configuración grabados y por evaluaciones de reglas *(verifica; la grabación continua cuesta más que la diaria)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Saber qué recursos incumplen una norma (cifrado, etiquetas, acceso público) | **Config** (reglas) |
| «¿Cómo estaba este recurso la semana pasada?» | **Config** (historial) |
| Evidencia de auditoría de configuración | **Config** + agregador |
| Corregir automáticamente un incumplimiento seguro y reversible | **Config** con remediación |
| **Impedir** que se cree un recurso incumplidor | No: [SCP](../organizations-scp/README.md) (Config detecta, no bloquea) |
| Saber **quién** hizo un cambio y cuándo | No: [CloudTrail](../cloudtrail-auditoria/README.md) |
| Control de gastos | No: [Budgets](../budgets-costos/README.md) |
| Cumplimiento a nivel de aplicación (reglas de negocio) | No: tu código |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Deriva (*drift*)** | Cuando la configuración real se aleja de la deseada |
| **Cumplimiento** | El veredicto de una regla sobre un recurso |
| **Evaluación** | El acto de aplicar una regla a un recurso |
| **Alcance de la regla** | A qué recursos se aplica (tipos, etiqueta, un recurso) |
| **Anotación** | Texto corto que explica por qué no cumple |
| **Remediación automática** | Corrección sin intervención; úsala solo para acciones seguras |
| **Evento «fuera de alcance»** | Aviso de que el recurso dejó de estar en el alcance de la regla |

## 5. Cómo se usa
1. Activa el **registrador** (todos los tipos soportados en producción) con un bucket cifrado y protegido: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Empieza con **reglas administradas** del catálogo (cifrado de buckets, volúmenes y bases, acceso público, etiquetas, usuario raíz sin claves).
3. Agrega una **regla de etiquetas** con tus claves obligatorias (`centro-costo`, `entorno`, `responsable`).
4. Solo si no existe una administrada, escribe una **regla personalizada** ([uso en Java](uso-en-java.md)).
5. Conecta los cambios de cumplimiento a **EventBridge** → SNS/tickets ([mensajería](../../07-mensajeria/README.md)).
6. Configura **remediación manual** primero; automática solo para acciones seguras.
7. Crea un **agregador** en la cuenta de seguridad para ver toda la organización ([`ejemplos/cli/config.sh`](ejemplos/cli/config.sh)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Rol del registrador** | Rol de servicio de Config con `AWS_ConfigRole` | Escribir en el bucket (`s3:PutObject`) y publicar en SNS |
| **Evaluador (Lambda de la regla)** | — | `config:PutEvaluations`; `config:GetResourceConfigHistory` para elementos grandes |
| **Pipeline** | `config:PutConfigRule`, `PutConfigurationRecorder`, `PutRemediationConfigurations`, `PutConfigurationAggregator` | — |
| **Consulta/auditoría** | `config:Describe*`, `Get*`, `SelectResourceConfig` | — |
| **Remediación** | Rol de SSM Automation con el permiso mínimo de la acción | — |

- **El bucket del historial es evidencia de auditoría:** cifrado con KMS, bloqueo de acceso público, retención y sin borrado por el equipo de aplicaciones.
- **La remediación automática modifica recursos:** rol acotado a una sola acción y recursos con etiqueta.
- Los elementos de configuración pueden contener **datos sensibles** de la configuración (nombres, políticas): limita quién los consulta.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Reglas administradas primero | Escribir una regla personalizada para lo que ya existe |
| Registrar todo en producción; elegir tipos en pruebas | Grabar tipos ruidosos que no evalúas y pagar por ello |
| Reportar `NOT_APPLICABLE` para recursos eliminados o fuera de alcance | Dejar evaluaciones pendientes |
| Anotaciones claras (qué falta) | Un `NON_COMPLIANT` sin explicación |
| Remediación manual al inicio; automática solo reversible | Remediar automáticamente borrando o apagando |
| Agregador y paquetes de conformidad por organización | Revisar cuenta por cuenta |
| Combinar con SCP (prevenir) y CloudTrail (quién) | Esperar que Config bloquee |
| Alarmar los cambios de cumplimiento críticos | Descubrir los incumplimientos en la auditoría |

## 8. Límites, costos y versiones
- **Costo:** por elemento de configuración grabado (continua frente a diaria) y por evaluación de regla *(verifica precios)*; el bucket de S3 y las ejecuciones de Lambda de reglas personalizadas aparte.
- **Límites** *(verifica)*: evaluaciones por llamada a `PutEvaluations` (100), anotación (256 caracteres), reglas por cuenta y región.
- **Terraform:** `aws_config_configuration_recorder`, `aws_config_delivery_channel`, `aws_config_configuration_recorder_status`, `aws_config_config_rule`, `aws_config_remediation_configuration`, `aws_config_configuration_aggregator`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 `config`; reglas personalizadas como función Lambda ([cómputo](../../04-compute/README.md)).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
