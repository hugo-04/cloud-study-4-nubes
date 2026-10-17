# AWS · Secretos · Systems Manager Parameter Store

**Parameter Store** (parte de AWS Systems Manager) es un **almacén jerárquico de configuración**: URLs, límites, banderas, versiones de imágenes y, cifrados con KMS, valores sensibles que no necesitan rotación automática. Es la opción simple y barata para la configuración de tus servicios.

## 1. Qué es

**Analogía:** un **archivador con carpetas** en la oficina. `/prod/pedidos/db/url` es el cajón «prod → pedidos → db» con la ficha «url». Cualquiera con permiso sobre la carpeta `/prod/pedidos/` puede leer todo lo que hay dentro, y cada ficha conserva su historial de cambios. Algunas fichas están en un sobre lacrado (cifradas con KMS).

```
 /prod/pedidos/
 ├─ db/url              (String)        jdbc:postgresql://pedidos...:5432/pedidos
 ├─ db/pool-max         (String)        20
 ├─ features/nueva-ui   (String)        true
 ├─ db/password         (SecureString)  ****  ← cifrada con KMS (ideal: Secrets Manager si necesita rotación)
 └─ colas/lista         (StringList)    pedidos-pagados,pedidos-enviados
```

## 2. Cómo funciona por dentro

### Tipos y niveles
| Tipo | Qué guarda |
|---|---|
| **String** | Texto |
| **StringList** | Valores separados por comas |
| **SecureString** | Texto cifrado con KMS (clave `aws/ssm` o tu CMK) |

| Nivel | Estándar | Avanzado |
|---|---|---|
| Tamaño | 4 KB | 8 KB |
| Cantidad | Hasta ~10 000 por cuenta/región | Hasta ~100 000 |
| Políticas de parámetro (caducidad, aviso) | No | **Sí** |
| Costo | Gratis | Por parámetro y por llamada *(verifica)* |

### Piezas
| Pieza | Qué es |
|---|---|
| **Nombre/ruta** | Jerarquía con `/` (hasta 15 niveles): `/entorno/servicio/grupo/clave` |
| **Versión** | Cada cambio crea una versión; el historial se consulta |
| **Etiquetas de versión** | Alias (`estable`, `candidata`) apuntando a una versión |
| **Parámetros públicos** | AWS publica los suyos (`/aws/service/…`, AMI recomendadas) |
| **Referencias** | `/aws/reference/secretsmanager/<nombre>` lee un secreto como si fuera parámetro |
| **Eventos** | Cambios y caducidades emiten eventos a EventBridge |

### Operaciones frecuentes
`GetParameter` (uno), `GetParameters` (hasta 10 por nombre), **`GetParametersByPath`** (toda una rama, con paginación y `Recursive`), `PutParameter`, `DeleteParameter(s)`, `GetParameterHistory`, `LabelParameterVersion`. Para `SecureString` hay que pedir `WithDecryption=true` y tener `kms:Decrypt`.

### Rendimiento
Hay un límite de transacciones por segundo por cuenta/región (hay un ajuste de **alto rendimiento** con costo; *verifica*). La solución normal: **leer al arrancar y cachear**.

### Parameter Store frente a Secrets Manager
| Aspecto | Parameter Store | Secrets Manager |
|---|---|---|
| Para qué | **Configuración** (y algunos secretos simples) | **Secretos** con rotación |
| Rotación automática | No | **Sí** |
| Costo | Estándar: gratis | Por secreto y por llamada |
| Jerarquía y lectura por rama | **Sí** (`GetParametersByPath`) | No (un secreto = un valor) |
| Réplica entre regiones | No nativa | **Sí** |
| Tamaño | 4 / 8 KB | 64 KB |
| Acceso entre cuentas | Solo parámetros avanzados compartidos (vía RAM) *(verifica)* | Política de recurso + CMK |

Regla práctica: **configuración → Parameter Store; credenciales que rotan → Secrets Manager.**

### Cuando necesitas más: AWS AppConfig
Para **banderas de funcionalidad y configuración dinámica** con validación, despliegue gradual y *rollback* automático, existe **AWS AppConfig** (otra parte de Systems Manager). Parameter Store es el almacén simple; AppConfig es el sistema de despliegue de configuración.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| URLs, límites, nombres de colas, versiones | **Parameter Store** (String) |
| Clave de API que nunca rota y pocas lecturas | SecureString (o Secrets Manager si quieres auditoría/rotación) |
| Contraseña de base de datos con rotación | **Secrets Manager** |
| Banderas con despliegue gradual | AppConfig |
| Datos de negocio (clientes, pedidos) | **No**: una base de datos |
| Valores que cambian por petición | **No** |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Ruta** | Nombre jerárquico: `/prod/pedidos/db/url` |
| **SecureString** | Parámetro cifrado con KMS |
| **Versión / etiqueta** | Historial y alias de versiones |
| **Nivel (tier)** | Estándar o avanzado |
| **Política de parámetro** | Caducidad y avisos (avanzado) |
| **GetParametersByPath** | Leer toda una rama |
| **Referencia a secreto** | Leer Secrets Manager por la API de parámetros |
| **AppConfig** | Despliegue gradual de configuración |

## 5. Cómo se usa
1. Define la **jerarquía**: `/<entorno>/<servicio>/<grupo>/<clave>`.
2. Crea los parámetros con **Terraform** (valores no sensibles): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Los `SecureString` se cargan fuera de banda (el valor quedaría en el estado).
3. Permisos **por ruta**: [`ejemplos/json/politica-lectura-por-ruta.json`](ejemplos/json/politica-lectura-por-ruta.json).
4. La aplicación lee **la rama completa al arrancar** y refresca cada N minutos.
5. Operación: [`ejemplos/cli/parametros.sh`](ejemplos/cli/parametros.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | `ssm:PutParameter` en `/<entorno>/<servicio>/*` | — |
| Aplicación | — | `ssm:GetParametersByPath`/`GetParameter` en **su** ruta (+ `kms:Decrypt` si hay SecureString) |
| Desarrolladores | `ssm:Describe*`, lectura de parámetros **no** seguros | — |
| Auditoría | `ssm:DescribeParameters`, historial | — |

- Los permisos por **ruta** son la clave del diseño: `arn:aws:ssm:<región>:<cuenta>:parameter/prod/pedidos/*`.
- Los `SecureString` usan una **CMK propia** si deben aislarse por equipo.
- **Endpoint de VPC** `ssm` ([Red](../../01-red/vpc-endpoints-privatelink/README.md)).
- Los cambios quedan en CloudTrail y en el historial del parámetro.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Jerarquía clara por entorno y servicio | Nombres planos (`url1`, `url2`) |
| Leer la rama una vez y cachear | `GetParameter` por cada petición |
| Permisos por ruta | `ssm:*` sobre `*` |
| Config no sensible como String | Todo como SecureString (cuesta KMS sin necesidad) |
| Rotación → Secrets Manager | Contraseñas rotativas en Parameter Store |
| Valores por defecto en la aplicación | Fallar al arrancar si falta una bandera opcional |
| Validar y tipar los valores | Confiar en que `"20"` es un número |

## 8. Límites, costos y versiones
- **Costo:** estándar gratis (límites de cantidad y tamaño); avanzado de pago; SecureString suma el costo de KMS. *Verifica precios y límites de transacciones por segundo.*
- **Límites** (verifica): 4 KB / 8 KB, 10 parámetros por `GetParameters`, profundidad de jerarquía, cantidad por cuenta.
- **Terraform:** `aws_ssm_parameter`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
