# AWS · Secretos · AWS Secrets Manager

**Secrets Manager** guarda, protege, entrega y **rota** secretos (contraseñas de bases de datos, claves de API, tokens) para que ni el código ni los repositorios los contengan.

## 1. Qué es

**Analogía:** la **caja de seguridad de un banco** con un empleado que cambia las combinaciones por ti. Tú no guardas la llave en el bolsillo: cada vez que alguien autorizado la necesita, la pide al banco; el banco apunta quién la pidió, y cada cierto tiempo cambia la combinación de la cerradura y de la caja a la vez.

```
 aplicación (rol IAM) ──GetSecretValue──► Secrets Manager ──descifra con KMS──► valor
                                              │
              rotación programada ──► Lambda de rotación ──► cambia la clave en la BASE y en el secreto
```

## 2. Cómo funciona por dentro

### El secreto y sus versiones
| Pieza | Qué es |
|---|---|
| **Secreto** | Contenedor con nombre (`prod/pedidos/db`), descripción, etiquetas, clave KMS y política |
| **ARN** | `arn:aws:secretsmanager:us-east-1:111122223333:secret:prod/pedidos/db-AbCdEf` (**sufijo aleatorio de 6 caracteres**) |
| **Valor** | Cadena (hasta 64 KB) o binario; lo normal es un **JSON** (`{"username":"…","password":"…"}`) |
| **Versión** | Cada cambio crea una versión con un `VersionId` |
| **Etiquetas de estado** | `AWSCURRENT` (la vigente), `AWSPREVIOUS` (la anterior), `AWSPENDING` (la que se está rotando) |
| **Política de recurso** | Quién puede usarlo, incluso desde otra cuenta |
| **Clave KMS** | `aws/secretsmanager` (gestionada) o una **clave propia (CMK)**; la CMK es obligatoria para acceso entre cuentas |
| **Réplicas** | Copia en otras regiones (recuperación ante desastres) |

### Operaciones frecuentes
`GetSecretValue` (por defecto `AWSCURRENT`), `BatchGetSecretValue`, `CreateSecret`, `PutSecretValue`, `UpdateSecret`, `RotateSecret`, `DescribeSecret`, `ListSecrets`, `DeleteSecret` (con **ventana de recuperación de 7 a 30 días**) y `RestoreSecret`.

### La rotación (lo que lo distingue)
1. Defines un **calendario** (cada N días o expresión cron).
2. Secrets Manager invoca una **función Lambda de rotación** con cuatro pasos:
   - `createSecret`: genera la nueva clave y la guarda como `AWSPENDING`.
   - `setSecret`: la aplica en la base de datos.
   - `testSecret`: prueba que funciona.
   - `finishSecret`: mueve `AWSCURRENT` a la nueva versión (la anterior pasa a `AWSPREVIOUS`).
3. Dos estrategias:
   - **Usuario único:** cambia la clave del mismo usuario (hay una ventana corta en que las conexiones nuevas pueden fallar).
   - **Usuarios alternos:** hay dos usuarios (`app` y `app_clone`) y se alterna; **sin cortes**.
4. **Rotación administrada** para algunos servicios (por ejemplo, la contraseña maestra de Aurora/RDS puede ser un secreto gestionado por el propio servicio).
5. La Lambda necesita **ruta de red** a la base de datos y a Secrets Manager (endpoint de VPC).

### Integraciones con el cómputo
| Cómputo | Cómo llega el secreto |
|---|---|
| **ECS** | En la definición de la tarea: `secrets: [{name, valueFrom: ARN[:clave-json::]}]`; lo lee el **rol de ejecución** al arrancar (no se refresca solo) |
| **EKS** | **Secrets Store CSI Driver** + proveedor de AWS (monta archivos; puede sincronizar a un Secret de Kubernetes), o *External Secrets Operator* |
| **Lambda** | Extensión de caché de parámetros y secretos, o el SDK con caché |
| **Aplicación Java** | SDK con caché propia (ver [uso en Java](uso-en-java.md)) o Spring Cloud AWS |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Contraseña de base de datos con rotación | **Secrets Manager** |
| Clave de API de un tercero | Secrets Manager (rotación manual o con Lambda propia) |
| Certificados, claves de firma | Secrets Manager (o ACM/KMS según el caso) |
| Configuración no secreta (URLs, banderas) | [Parameter Store](../parameter-store/README.md) (más barato) |
| Cifrar datos de la aplicación | **KMS**, no Secrets Manager |
| Un secreto por cada petición/usuario | **No**: es una bóveda de credenciales, no una base de datos |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Secreto** | Contenedor con versiones |
| **Etiqueta `AWSCURRENT`** | La versión vigente |
| **Rotación** | Cambiar la credencial de forma automática y coordinada |
| **Usuarios alternos** | Rotación sin cortes con dos usuarios |
| **Ventana de recuperación** | Tiempo (7–30 días) para deshacer un borrado |
| **Réplica** | Copia en otra región |
| **Política de recurso** | Permisos pegados al secreto |
| **CMK** | Clave KMS propia, necesaria entre cuentas |

## 5. Cómo se usa
1. Elige la **convención de nombres**: `entorno/servicio/recurso` (`prod/pedidos/db`).
2. Crea el secreto con **Terraform** (contenedor + política + rotación): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. El **valor** nunca pasa por Git ni por el estado de Terraform: entra por la consola/CLI o lo crea el servicio (RDS administrado).
4. Da permiso **solo** al rol que lo lee: [`ejemplos/json/`](ejemplos/json/).
5. La aplicación lo lee con **caché** y reacciona a la rotación.
6. Operación y auditoría: [`ejemplos/cli/secretos.sh`](ejemplos/cli/secretos.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | `secretsmanager:CreateSecret`, `PutResourcePolicy`, `RotateSecret` (sin leer valores) | — |
| Aplicación | — | `secretsmanager:GetSecretValue` sobre **su** secreto (+ `kms:Decrypt` si hay CMK) |
| Persona de guardia | `DescribeSecret` | `GetSecretValue` solo con aprobación (break glass) |
| Lambda de rotación | `PutSecretValue`, `UpdateSecretVersionStage`, `GetSecretValue` | Acceso de red y credenciales de administrador a la base |

- Política IAM con el **ARN completo** (con `-??????` al final si usas el nombre).
- **Endpoint de VPC** para `secretsmanager` ([Red](../../01-red/vpc-endpoints-privatelink/README.md)) y condición `aws:SourceVpce` si quieres cerrarlo.
- **CMK** propia para secretos sensibles y acceso entre cuentas.
- Todas las lecturas quedan en **CloudTrail**; alarma ante lecturas inesperadas.
- Etiquetas y ABAC para dar permisos por equipo.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Rotación automática con usuarios alternos | Contraseñas eternas |
| Caché con TTL en la aplicación | `GetSecretValue` en cada petición |
| Reaccionar a fallos de autenticación (recargar) | Asumir que el secreto no cambia |
| Nombre jerárquico y etiquetas | Nombres como `secreto1` |
| Permisos por ARN | `secretsmanager:*` sobre `*` |
| Ventana de recuperación de 30 días | Borrado forzado sin recuperación |
| Valor fuera de Git y del estado de Terraform | `secret_string` en el código |
| Parameter Store para lo no secreto | Un secreto por cada bandera de configuración |

## 8. Límites, costos y versiones
- **Costo:** por **secreto al mes** y por **10 000 llamadas a la API**; las réplicas cuentan como secretos; las claves CMK de KMS se cobran aparte. *Verifica precios vigentes.* La caché reduce llamadas.
- **Límites** (verifica): 64 KB por valor, versiones con etiqueta, solicitudes por segundo de `GetSecretValue`.
- **Terraform:** `aws_secretsmanager_secret`, `aws_secretsmanager_secret_policy`, `aws_secretsmanager_secret_rotation`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
