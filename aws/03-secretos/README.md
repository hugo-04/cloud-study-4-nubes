# AWS · 03 Secretos y configuración

Un microservicio necesita tres cosas que **no deben vivir en el código**: credenciales, claves de cifrado y configuración. Este capítulo reúne las tres piezas de AWS que las resuelven.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Secrets Manager](secrets-manager/README.md) | ¿Dónde guardo una **credencial** y quién la rota? | La caja fuerte con cambio automático de combinación | Contraseñas de base de datos, claves de API, con rotación, versiones y réplica entre regiones |
| [KMS](kms/README.md) | ¿Con qué **llave** se cifra todo esto? | La cerrajería central que fabrica y custodia las llaves maestras | Claves de cifrado para S3, EBS, RDS, SQS, Secrets Manager, cifrado de sobre y firmas |
| [Parameter Store](parameter-store/README.md) | ¿Dónde guardo la **configuración** del servicio? | El archivador con carpetas por entorno y servicio | URLs, límites, banderas, nombres de colas; secretos simples sin rotación |

> Las tres se **apoyan**: Secrets Manager y los `SecureString` de Parameter Store se cifran con una clave de **KMS**; el rol de la aplicación recibe permisos de los tres con IAM ([capítulo 02](../02-iam/README.md)).

## Árbol de decisión: «quiero guardar…»

```
¿Es una contraseña/credencial que debe ROTAR sola (base de datos, API)?
   └─ Secrets Manager (+ clave KMS propia si debe aislarse)

¿Es una URL, un número, una bandera, la lista de colas?
   └─ Parameter Store (String / StringList)

¿Es un secreto estático, pocas lecturas, sin necesidad de rotación ni réplica?
   └─ Parameter Store SecureString (más barato) o Secrets Manager si quieres auditoría fina

¿Quiero cifrar un campo o un archivo de MI aplicación?
   └─ KMS: GenerateDataKey + AES-GCM (cifrado de sobre)

¿Quiero que S3 / SQS / RDS / EBS cifren con MI clave?
   └─ KMS: clave gestionada por el cliente (CMK) + permisos en la política de clave

¿Quiero firmar o verificar (JWT, documentos)?
   └─ KMS: clave asimétrica de firma

¿Quiero cambiar una bandera de funcionalidad gradualmente, con rollback?
   └─ AppConfig (parte de Systems Manager)

¿Son datos de negocio (clientes, pedidos)?
   └─ Ninguna: es una base de datos
```

## Comparativa

| Característica | Secrets Manager | KMS | Parameter Store |
|---|---|---|---|
| **Guarda** | Secretos (hasta 64 KB) | **Claves**, no datos | Configuración (4/8 KB) y SecureString |
| **Rotación automática** | **Sí** (Lambda de rotación) | Rotación de la clave (automática, anual o configurable) | No |
| **Jerarquía / lectura por rama** | No | No (alias) | **Sí** |
| **Versiones** | Etapas (`AWSCURRENT`, `AWSPREVIOUS`) | Versiones de material de la clave | Versiones numeradas y etiquetas |
| **Réplica entre regiones** | **Sí** | Claves multi-región | No nativa |
| **Control de acceso** | IAM + política de recurso | IAM + **política de clave** (obligatoria) | IAM por ruta |
| **Costo** | Por secreto y por llamada | Por clave y por llamada | Estándar gratis; avanzado de pago |
| **Error típico** | Leer el secreto en cada petición | Política de clave sin administrador | Contraseñas rotativas aquí |

*(Precios y cuotas: verifica en la documentación oficial.)*

## La receta ModaLima

| Dato | Dónde vive | Quién lo lee |
|---|---|---|
| Contraseña de la base de Pedidos | Secrets Manager, rotación cada 30 días, cifrada con la CMK `prod-pedidos` | Rol de la tarea de Pedidos |
| Clave de la API de pagos | Secrets Manager (sin rotación automática, rotación manual con alerta) | Rol de Pagos |
| URL de base, tamaño del pool, timeouts | Parameter Store `/prod/pedidos/...` (String) | Rol de Pedidos (solo su rama) |
| Lista de colas, banderas simples | Parameter Store (StringList / String) | Rol de Pedidos |
| Cifrado de S3, SQS, RDS | CMK por dominio (`prod-pedidos`, `prod-pagos`) | Servicios, vía política de clave |
| Cifrado de campos sensibles (documento del cliente) | Cifrado de sobre con la CMK `prod-pedidos` | Aplicación de Pedidos |

## Orden recomendado de adopción
1. **Una CMK por dominio y entorno** (no una para toda la cuenta), con administradores y usuarios separados.
2. **Todas las credenciales a Secrets Manager**; adiós a variables de entorno con contraseñas.
3. **Jerarquía de Parameter Store** `/<entorno>/<servicio>/...` y permisos por ruta.
4. **Rotación automática** de la base de datos, con el cliente preparado (reintento y caché con TTL).
5. **Endpoints de VPC** para `secretsmanager`, `kms` y `ssm` ([Red](../01-red/vpc-endpoints-privatelink/README.md)).
6. **Todo como código** (capítulo 10): claves, secretos (contenedor), parámetros y políticas.

## Reglas transversales
- **El valor de un secreto nunca** va a logs, métricas, tickets, endpoints de depuración ni estado de Terraform.
- **Permisos por recurso y por ruta**, no `secretsmanager:*` ni `ssm:*` sobre `*`.
- **Cachear con TTL** y tolerar el fallo del servicio (conservar la última lectura buena).
- **Rotación = el cliente debe poder cambiar de credencial sin reiniciar** (o reiniciar sin pérdida).
- **Una política de clave KMS siempre tiene administrador** distinto del usuario de la clave.
- **Contexto de cifrado** en todo uso de KMS: es auditoría y defensa contra el uso de un cifrado fuera de lugar.
- **Borrado con ventana de espera:** las claves y los secretos se programan para borrar, no se borran al instante.

## Java: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Secrets Manager | Caché con TTL, reintento por rotación, refresco de la contraseña del pool, `CredentialsProvider` en Quarkus | Núcleo puro + lector SDK + caché |
| KMS | Cifrado de sobre AES-GCM con contexto, SSE-KMS en S3 | Proveedor de claves intercambiable (se prueba sin AWS) |
| Parameter Store | Lectura de la rama, valores tipados con defaults, caché con «última buena», `ConfigSource` en Quarkus | Lector + `Configuracion` pura + caché |

Reglas comunes: **un cliente SDK por aplicación** (thread-safe), **funciones puras** para las reglas, y en reactivo todo lo bloqueante va a `boundedElastic` / pool de trabajadores.

## Cómo se relacionan con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): cuentas, regiones y costos.
- [Red](../01-red/README.md): endpoints de VPC para llegar a los tres servicios sin salir a Internet.
- [IAM](../02-iam/README.md): roles de tarea/pod que reciben los permisos; IRSA y Pod Identity.
- [Compute](../04-compute/README.md): cómo ECS, EKS y Lambda inyectan secretos y parámetros.
- [Datos](../08-datos/README.md): contraseñas de RDS/Aurora gestionadas y cifrado.
- [Terraform en AWS](../10-terraform/README.md): estado seguro y secretos fuera del estado.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON), troubleshooting, repaso y prompt de NotebookLM.
