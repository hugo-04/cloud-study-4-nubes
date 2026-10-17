# AWS · Red · VPC Endpoints, PrivateLink y Route 53 privado

Cómo llegar a servicios de AWS (S3, SQS, Secrets Manager, ECR…) y a servicios de otras cuentas **sin salir a internet**: por dentro de la red de AWS, con IP privadas. Y cómo resolver los nombres para que eso funcione.

## 1. Qué es

**Analogía:** el edificio tiene una **puerta interna al banco** (el servicio de AWS) en el mismo complejo: en vez de salir a la calle (NAT/internet) y entrar por la fachada, usas el pasillo interno. Hay dos tipos de pasillo: uno es un **letrero en el mapa** (endpoint de puerta de enlace: una ruta), otro es una **ventanilla propia dentro de tu piso** (endpoint de interfaz: una tarjeta de red con IP privada).

```
 sin endpoint:   contenedor → NAT → internet → sqs.us-east-1.amazonaws.com        (paga NAT, sale a internet)
 gateway (S3):   contenedor → tabla de rutas (pl-xxxx → vpce-gw) → S3             (gratis, solo S3 y DynamoDB)
 interfaz:       contenedor → 10.20.100.37 (ENI del endpoint) ══PrivateLink══► SQS (DNS privado)
```

## 2. Cómo funciona por dentro

### Tipos de endpoint

| Tipo | Cómo se conecta | Servicios | Costo |
|---|---|---|---|
| **Gateway** | Entrada en la **tabla de rutas** hacia una lista de prefijos | **S3 y DynamoDB** | **Gratis** |
| **Interface** (PrivateLink) | **ENI con IP privada** en tus subredes (una por AZ) | La mayoría de servicios de AWS, SaaS y servicios propios | Por hora **por AZ** + por GB |
| **Gateway Load Balancer** | Inserta aparatos de inspección en la ruta | Firewalls de terceros | Por hora + por GB |
| **Resource / Service Network** | Acceso a un recurso concreto o a una red de servicios (VPC Lattice) | Casos avanzados | Verifica |

### Endpoint de interfaz paso a paso
1. Eliges el servicio (`com.amazonaws.us-east-1.sqs`), la VPC, las subredes (una por AZ) y un **grupo de seguridad** (443 desde tus apps).
2. AWS crea una **ENI por subred** con IP privada.
3. Con **DNS privado** activado, el nombre normal (`sqs.us-east-1.amazonaws.com`) **resuelve a esas IP privadas dentro de la VPC**: el código no cambia.
4. Una **política de endpoint** (JSON) puede limitar qué acciones y recursos se permiten a través de él.

Requisitos para el DNS privado: la VPC con `enableDnsSupport` y `enableDnsHostnames` activos.

### Endpoint de puerta de enlace (S3/DynamoDB)
No tiene IP: AWS añade a la tabla de rutas una entrada hacia una **lista de prefijos** administrada (`pl-...`) con los rangos del servicio. Solo sirve **dentro de la misma región** y **no se extiende** por peering, VPN ni Direct Connect.

### PrivateLink para tu propio servicio
Un equipo publica su servicio detrás de un **Network Load Balancer** y crea un **endpoint service**; los consumidores (otras VPC/cuentas) crean un endpoint de interfaz. Solo expone **ese servicio** (no toda la red), **sin importar si los CIDR se solapan**, y puede requerir aprobación.

### Route 53: zonas privadas y Resolver
- **Zona alojada privada:** nombres internos (`pedidos.modalima.internal`) visibles solo en las VPC que asocies.
- **Route 53 Resolver:** el DNS de la VPC (base +2). Para redes híbridas: **endpoint entrante** (la red local consulta nombres de AWS) y **saliente** con reglas de reenvío (AWS consulta nombres de la red local).
- Con un endpoint de interfaz y DNS privado, AWS crea y asocia la zona privada por ti.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Contenedores privados que escriben a S3 | **Gateway de S3** (gratis) |
| Fargate/ECS/EKS en subredes sin NAT | Interfaz para `ecr.api`, `ecr.dkr`, `logs`, `sts`, `secretsmanager` + gateway de S3 (las capas de ECR viven en S3) |
| Exponer un servicio a otra cuenta sin peering | **PrivateLink** (endpoint service) |
| Pocas llamadas a un servicio raro | NAT puede costar menos que un endpoint por hora y por AZ |
| Regiones distintas | Gateway no sirve entre regiones; usa interfaz con endpoint regional o peering |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Lista de prefijos administrada** | Los rangos del servicio, mantenidos por AWS |
| **Política de endpoint** | Qué acciones y recursos se permiten por ese endpoint |
| **DNS privado** | Hace que el nombre público resuelva a la IP privada del endpoint |
| **Endpoint service** | Tu servicio publicado por PrivateLink |
| **Zona alojada privada** | Dominio visible solo en ciertas VPC |
| **Resolver entrante/saliente** | Puentes de DNS con la red local |
| **`aws:SourceVpce`** | Condición IAM/bucket para exigir un endpoint |

## 5. Cómo se usa
1. Siempre el **gateway de S3 y DynamoDB** (gratis) en las tablas de rutas de app.
2. Interfaz solo para los servicios que realmente usas, **una por AZ** que uses.
3. Un SG de endpoints: 443 desde el SG de las apps.
4. Verifica el DNS **desde dentro** ([diagnóstico](../diagnostico-conectividad/README.md)): debe resolver a IP privada.
5. En S3, exige el endpoint con una política de bucket (`aws:SourceVpce`).
6. Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf); políticas: [`ejemplos/json/`](ejemplos/json/); CLI: [`ejemplos/cli/endpoints.sh`](ejemplos/cli/endpoints.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | `ec2:*VpcEndpoint*`, `route53:*` acotado | — |
| Apps | — | Sus acciones IAM de siempre; la política de endpoint **recorta**, no amplía |
| Seguridad | `ec2:DescribeVpcEndpoints`, Config | — |

- La política de endpoint **no sustituye** a IAM: ambas deben permitir.
- Política de bucket con `aws:SourceVpce` o `aws:SourceVpc`: datos accesibles **solo** desde tus endpoints.
- Servicios propios por PrivateLink: **aprobación manual** de conexiones y lista de cuentas permitidas.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Gateway de S3/DynamoDB en todas las VPC | Mandar S3 por el NAT |
| Interfaz en cada AZ que uses | Un endpoint en una sola AZ para tráfico de tres |
| DNS privado activo y verificado | Cambiar el código a `endpointOverride` sin necesidad |
| Política de endpoint con lo mínimo | `Principal: *`, `Action: *` sin condición |
| Conectar con PrivateLink servicios entre equipos | Peering de redes completas para exponer un solo servicio |
| Crear los endpoints con Terraform y etiquetas | Crear a mano en la consola |

## 8. Límites, costos y versiones
- **Costo:** gateway gratis; interfaz = **por hora y por AZ** + **por GB**. 10 endpoints × 3 AZ son 30 ENI cobradas por hora. *Verifica precios.* Compara contra el costo del NAT por GB.
- **Límites típicos** (verifica): endpoints por VPC, ancho de banda por ENI de endpoint.
- **Terraform:** `aws_vpc_endpoint`, `aws_vpc_endpoint_service`, `aws_route53_zone`/`aws_route53_record`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
