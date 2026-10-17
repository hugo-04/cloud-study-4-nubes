# AWS · 00 Fundamentos

Todo lo que necesitas entender de AWS **antes** de tocar un servicio concreto: dónde vive cada recurso, cómo se organizan cuentas, permisos y costos, cómo se habla con la nube y cómo se nombran las cosas.

---

## 1. Qué es AWS (con analogía)

**AWS es una ciudad de servicios públicos que se alquilan por uso: electricidad, agua, transporte, bodegas.** No construyes la planta eléctrica; conectas tu casa, pagas el medidor y tú decides quién tiene llave de cada habitación. Cada **cuenta de AWS** es como un terreno con su propia escritura, su propio medidor y su propia cerca: lo que pasa en un terreno no afecta a los demás salvo que tú abras una puerta.

---

## 2. Cómo funciona por dentro: cuentas, organización y recursos

```
Organización (cuenta de administración)
 └─ Raíz
     ├─ OU Plataforma      ── cuenta de red, cuenta de registros/seguridad, cuenta de herramientas
     ├─ OU Cargas          ── cuenta dev · cuenta qa · cuenta prod  (una por entorno y a veces por equipo)
     ├─ OU Sandbox         ── cuentas de laboratorio con presupuesto bajo
     └─ OU Suspendidas     ── cuentas cerradas o en espera
          └─ cada cuenta contiene recursos (casi todos viven en UNA región)
```

| Concepto | Qué es | Para qué |
|---|---|---|
| **Cuenta (Account)** | Contenedor de recursos con ID de 12 dígitos; **frontera fuerte** de seguridad, facturación y límites | Separar entornos y equipos |
| **AWS Organizations** | Agrupa cuentas, factura en conjunto y aplica reglas | Gobierno multicuenta |
| **OU (Unidad organizativa)** | Carpeta de cuentas dentro de la organización | Aplicar políticas a un grupo |
| **SCP (Service Control Policy)** | Techo de permisos para cuentas/OU: lo que **no** se puede hacer aunque IAM lo permita | Guardarraíles |
| **IAM Identity Center** | Acceso único de personas a varias cuentas | Que nadie use usuarios de IAM con claves |
| **Región** | Ubicación geográfica con centros de datos (`us-east-1`, `sa-east-1`…) | Latencia, cumplimiento, precios |
| **Zona de disponibilidad (AZ)** | Uno o más centros de datos aislados dentro de una región | Alta disponibilidad |
| **Recurso** | Cualquier cosa que creas (instancia, bucket, cola…) | — |
| **ARN** | Nombre único global de un recurso | Permisos y referencias |

> **La cuenta es el aislamiento.** En AWS la cuenta es el límite fuerte de aislamiento: los **permisos entre cuentas están cerrados por defecto**: hay que abrirlos explícitamente (con roles).

**Un ARN, por partes:** `arn:aws:s3:::modalima-comprobantes-prod/pedidos/123.pdf` → `arn` : `partición` (`aws`, `aws-cn`, `aws-us-gov`) : `servicio` : `región` : `cuenta` : `recurso`. Algunos servicios (S3) omiten región y cuenta porque el nombre ya es global; la mayoría los incluyen: `arn:aws:sqs:us-east-1:111122223333:pedidos-creados`.

---

## 3. Regiones, zonas y alcance de los servicios

- Una **región** es un conjunto independiente de zonas. Los datos **no salen** de la región salvo que tú lo configures.
- Una región tiene **al menos tres AZ** (verifica por región). Las AZ están separadas por kilómetros, con energía y red propias, y conectadas por fibra de baja latencia.
- Los **nombres** de AZ (`us-east-1a`) se **barajan por cuenta**: tu `1a` puede ser otro edificio que el `1a` de otra cuenta. Para coordinar entre cuentas usa el **ID de AZ** (`use1-az1`).
- **Servicios regionales** (la mayoría): VPC, EC2, S3 (el bucket vive en una región), SQS, RDS…
- **Servicios globales o con plano global:** IAM, Organizations, Route 53, CloudFront, WAF para CloudFront, Global Accelerator. Algunos tienen un detalle en `us-east-1` (por ejemplo, los certificados de ACM para CloudFront deben estar allí; verifica en la doc oficial).
- Además: **zonas locales** y **ubicaciones de borde** (CDN) acercan servicios a los usuarios.

| Objetivo | Estrategia |
|---|---|
| Alta disponibilidad (HA) | Varias **AZ** de la misma región |
| Recuperación ante desastres (DR) | Otra **región** (copias, réplicas, infraestructura como código) |
| Baja latencia para usuarios | Región cercana + CloudFront |
| Cumplimiento (datos en un país) | Región dentro del país + políticas que impidan otras regiones |

> **Elegir región:** latencia, **precio** (varía por región), **servicios disponibles** y requisitos legales. Una vez elegida, es costoso moverse.

---

## 4. Modelos de servicio con nombres de AWS

| Nivel | Tú administras | AWS administra | Ejemplos AWS |
|---|---|---|---|
| **IaaS** | SO, runtime, app | Hardware, virtualización | EC2 |
| **CaaS** | Imágenes y configuración | Orquestación, nodos (si Fargate) | ECS, EKS, Fargate |
| **PaaS** | Tu aplicación | Plataforma y servidores | App Runner, Elastic Beanstalk, RDS |
| **FaaS / serverless** | Tu función | Todo lo demás | Lambda, Step Functions |
| **SaaS** | Solo datos y usuarios | Todo | Amazon Connect, WorkMail |

---

## 5. Responsabilidad compartida

| AWS es responsable de la seguridad **DE** la nube | Tú eres responsable de la seguridad **EN** la nube |
|---|---|
| Centros de datos, hardware, red global, hipervisores | Identidades y permisos (IAM), configuración de red, grupos de seguridad |
| Disponibilidad y parches de los servicios administrados | Datos, cifrado, claves, copias de seguridad |
| Cumplimiento de la infraestructura | Parches del SO en EC2, código y dependencias de tu aplicación |

Cuanto más administrado es el servicio, **más hace AWS y menos tú**, pero **identidad, datos y configuración siempre son tuyos**.

---

## 6. Cómo se habla con AWS

| Forma | Para qué | Cuándo |
|---|---|---|
| **Consola** (console.aws.amazon.com) | Explorar y aprender | Primeros pasos |
| **CloudShell** | Terminal en el navegador, ya autenticada | Probar sin instalar nada |
| **AWS CLI v2** (`aws`) | Comandos reproducibles | Laboratorios y scripts |
| **SDK** (Java: `software.amazon.awssdk:*`) | Desde tu código | Aplicaciones |
| **IaC** (Terraform, CloudFormation, CDK) | Infraestructura como código | Todo lo serio |
| **API HTTP firmada (SigV4)** | Integraciones | Casos avanzados |

Todo es una **llamada a la API del servicio**, firmada con credenciales. Consola, CLI y Terraform hacen las mismas llamadas, por eso lo creado en la consola aparece de inmediato en la CLI.

```bash
aws configure sso                              # configurar acceso por IAM Identity Center (recomendado)
aws sso login --profile modalima-dev           # iniciar sesión
aws sts get-caller-identity --profile modalima-dev   # ¿QUIÉN soy y en QUÉ cuenta estoy?  (equivale a mirar dónde estás parado)
aws ec2 describe-regions --query "Regions[].RegionName" --output text
export AWS_PROFILE=modalima-dev AWS_REGION=us-east-1
aws s3 mb s3://modalima-estudio-<sufijo-unico> # un bucket de práctica
aws s3 rb s3://modalima-estudio-<sufijo-unico> --force   # limpieza
```

> **Antes de crear nada, ejecuta `aws sts get-caller-identity`.** El error más caro es crear recursos en la cuenta (o región) equivocada.

### Cómo el SDK de Java encuentra sus credenciales
El SDK v2 prueba, **en este orden**, una **cadena de proveedores**: propiedades del sistema → variables de entorno (`AWS_ACCESS_KEY_ID`…) → token de identidad web (el de **IRSA** en EKS) → perfil compartido o **SSO** (`~/.aws`) → credenciales del **contenedor** (ECS y *Pod Identity*) → **perfil de instancia** de EC2. En un servicio en producción **no hay claves**: la plataforma entrega credenciales temporales al rol del servicio. La región sale de `AWS_REGION` o del perfil.

```java
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

public class DondeEstoyParado {
    public static void main(String[] args) {
        try (StsClient sts = StsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build()) {
            GetCallerIdentityResponse quien = sts.getCallerIdentity();
            System.out.println("cuenta=" + quien.account() + " identidad=" + quien.arn());
        }
    }
}
```

---

## 7. Costos

- **Pago por uso**, por segundo/hora/GB/solicitud según el servicio.
- **Compromisos:** *Savings Plans* y *Reserved Instances* dan descuentos por comprometer uso estable; *Spot* da capacidad barata que AWS puede quitarte.
- **Nivel gratuito:** cambia con el tiempo y depende de cuándo creaste la cuenta; **verifica el vigente** en la doc oficial.
- **Los costos que sorprenden:**
  - **NAT Gateway:** por hora **y por GB procesado**.
  - **Transferencia de datos:** salida a internet, entre **AZ** y entre regiones.
  - **IPv4 pública:** se cobra por hora por cada dirección.
  - **Recursos olvidados:** volúmenes, balanceadores, endpoints, instantáneas.
  - **Registros (CloudWatch Logs):** ingesta y almacenamiento sin retención.
- Para repartir costos por equipo hay que **activar las etiquetas** como *etiquetas de asignación de costos* en Facturación.

```bash
# Presupuesto mensual con alerta del 80 % (el correo va dentro de notifications.json; verifica los parámetros vigentes)
aws budgets create-budget --account-id <ID-12-DIGITOS> \
  --budget '{"BudgetName":"mensual-dev","BudgetLimit":{"Amount":"100","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers file://notifications.json
```

---

## 8. Etiquetas y nombres

**Etiquetas (tags)** = pares clave-valor para organizar, repartir costos y aplicar permisos (hasta 50 por recurso; distinguen mayúsculas).

| Clave | Ejemplo | Para qué |
|---|---|---|
| `env` | `prod` | Entorno |
| `owner` | `equipo-pedidos` | Responsable |
| `app` | `tienda` | Aplicación |
| `costcenter` | `CC-1001` | Reparto de costos |

**Nombres:** adopta una convención desde el día 1, por ejemplo `<servicio>-<app>-<env>`: `sqs-pedidos-prod`. Reglas que muerden: los **buckets de S3** tienen nombre **único en todo el mundo** (3–63 caracteres, minúsculas); algunos servicios no aceptan mayúsculas o guiones bajos; los nombres de varios recursos **no se pueden cambiar**.

---

## 9. Seguridad básica desde el día 1

1. **Cuenta raíz:** actívale MFA, **no la uses** para el día a día y no le crees claves de acceso.
2. **Personas por IAM Identity Center**, no usuarios de IAM con claves permanentes.
3. **Cargas con roles**, no claves: roles de instancia, de tarea, de función o de pod.
4. **CloudTrail** activo en todas las regiones y enviado a una cuenta de registros.
5. **Bloquear el acceso público** de S3 a nivel de cuenta.
6. **GuardDuty** y alertas de presupuesto desde el inicio.
7. **Mínimo privilegio** y por recurso; evita `"Action": "*"`.

---

## 10. Caso real inventado: ModaLima

Tienda online de ropa, 6 personas de tecnología.

- **Problema:** en campaña el servidor propio se caía; el resto del año estaba ocioso.
- **Paso 1:** mover la aplicación a **ECS con Fargate** detrás de un balanceador, con escalado automático.
- **Paso 2:** base de datos **Aurora PostgreSQL** con copias automáticas.
- **Paso 3:** separar `dev`, `qa` y `prod` en **cuentas distintas** bajo **Organizations**, con un presupuesto y alerta por cada una y acceso por **IAM Identity Center**.
- **Resultado:** cero caídas en la siguiente campaña y factura predecible.
- **Lección:** la nube no es «poner el servidor en otro lado»; es cambiar a servicios administrados, separar entornos y controlar costos.

---

## 11. Qué hacer y qué NO hacer

**Qué hacer**
- Una **cuenta por entorno** (y por equipo cuando crezca), bajo Organizations.
- Presupuesto con alerta **el primer día**.
- Etiquetar y nombrar con convención desde el inicio.
- Roles de corta duración y **mínimo privilegio**; permisos por recurso.
- Todo en código (Terraform/CloudFormation) y en Git.

**Qué NO hacer**
- Trabajar con la cuenta raíz o con `AdministratorAccess` «para que no falle».
- Crear recursos en la cuenta o región equivocada por no verificar `sts get-caller-identity`.
- Dejar recursos de prueba encendidos.
- Poner IP pública a todo «para que funcione».
- Guardar claves de acceso en el repositorio o en variables de entorno de producción.
- Elegir región sin revisar los servicios y precios.

---

## 12. Glosario

| Término | Significado simple |
|---|---|
| Cuenta | Contenedor de recursos, permisos y facturación |
| Organizations | Servicio que agrupa cuentas y les aplica reglas |
| OU | Carpeta de cuentas |
| SCP | Techo de permisos que IAM no puede superar |
| Región / AZ | Zona geográfica / centro de datos aislado dentro de ella |
| ARN | Nombre único de un recurso |
| IAM | Identidades y permisos |
| STS | Servicio de credenciales temporales |
| Rol | Identidad asumible con credenciales temporales |
| VPC | Tu red privada virtual |
| Tag | Etiqueta clave-valor |
| RPO / RTO | Datos que puedes perder / tiempo que puedes estar caído |
| IaC | Infraestructura definida en código |
| Serverless | No administras servidores; pagas por ejecución |
