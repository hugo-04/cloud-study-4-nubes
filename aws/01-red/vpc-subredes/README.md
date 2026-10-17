# AWS · Red · VPC y subredes

La **VPC** (Virtual Private Cloud) es tu red privada dentro de AWS: el terreno cercado donde pones tus servidores, contenedores, bases de datos y balanceadores. Todo lo demás del capítulo de red (grupos de seguridad, endpoints, peering) se apoya en esto.

## 1. Qué es

**Analogía:** un conjunto residencial. La **VPC** es todo el conjunto con su muro; las **subredes** son las torres (cada una en un edificio distinto = una **zona de disponibilidad**); la **tabla de rutas** son las señales que dicen por dónde se sale; la **puerta principal** es el *Internet Gateway* y el **portero que sale a hacer mandados por los vecinos** es el *NAT Gateway* (los de adentro pueden salir, los de afuera no pueden entrar).

```
 VPC 10.20.0.0/16 (región us-east-1)
 ├─ AZ-a ─ pública 10.20.0.0/24 ── ALB, NAT-a      ─┐ ruta 0.0.0.0/0 → Internet Gateway
 │         app     10.20.16.0/22 ── contenedores     │ ruta 0.0.0.0/0 → NAT-a
 │         datos   10.20.100.0/24 ─ Aurora, ElastiCache  sin ruta a internet
 ├─ AZ-b ─ (lo mismo, con su propio NAT-b)
 └─ AZ-c ─ (lo mismo, con su propio NAT-c)
```

## 2. Cómo funciona por dentro

### Las piezas

| Pieza | Qué es | Detalle que importa |
|---|---|---|
| **VPC** | Red virtual **regional** con un bloque CIDR IPv4 (de `/16` a `/28`) | Puedes añadir bloques secundarios; **no puedes cambiar** el primario |
| **Subred** | Porción de la VPC en **una sola AZ** | Pública o privada **según su tabla de rutas**, no por su nombre |
| **Tabla de rutas** | Dice a dónde va cada destino | Cada subred se asocia a una; la ruta más específica gana |
| **Internet Gateway (IGW)** | Puerta bidireccional a internet | Una por VPC; es alta disponibilidad por diseño |
| **NAT Gateway** | Permite salir a internet a los privados sin que entren | **Vive en una AZ**: usa uno por AZ para alta disponibilidad |
| **Egress-only IGW** | Lo mismo que NAT, para IPv6 | — |
| **Elastic IP** | IP pública fija | Se cobra por hora cada IPv4 pública |
| **Conjunto de opciones DHCP** | DNS y dominio de la VPC | El DNS de la VPC está en la base +2 (p. ej. `10.20.0.2`) |
| **Registros de flujo (Flow Logs)** | Metadatos de tráfico (origen, destino, puerto, aceptado/rechazado) | La herramienta número uno de diagnóstico |

### Direcciones reservadas
AWS reserva **5 direcciones por subred** (las cuatro primeras y la última): red, enrutador de la VPC, DNS, uso futuro y difusión. Una `/24` ofrece **251** utilizables. **EKS y otros servicios consumen IP de la subred por cada pod/interfaz**, así que subredes pequeñas se agotan.

### Qué hace pública a una subred
Una subred es **pública** si su tabla de rutas tiene `0.0.0.0/0 → Internet Gateway`. Que un recurso sea alcanzable desde internet además requiere una **IP pública** y que los grupos de seguridad lo permitan. **Privada** = sin esa ruta.

### Planificar las direcciones (lo más difícil de cambiar)
- Usa rangos privados RFC 1918 (`10/8`, `172.16/12`, `192.168/16`) y **reserva un bloque por entorno y región** en una hoja o servicio central.
- **No solapar** con otras VPC, la red local ni otras nubes que algún día conectes.
- Deja espacio: sobredimensionar cuesta cero; **redimensionar** cuesta una migración.

| Nivel | Tamaño típico (ModaLima) | Por qué |
|---|---|---|
| VPC | `/16` (65 536) | Margen para años |
| Públicas | `/24` por AZ | Solo balanceadores y NAT |
| Aplicación | `/22` por AZ | Contenedores y pods consumen muchas IP |
| Datos | `/24` por AZ | Bases de datos, cachés |
| Endpoints / herramientas | `/26`–`/24` por AZ | Interfaces de PrivateLink |

## 3. Para qué sirve y cuándo NO

| Situación | ¿Qué haces? |
|---|---|
| Microservicios en ECS/EKS con bases privadas | VPC con tres niveles de subredes y tres AZ |
| Un experimento de una tarde | La **VPC predeterminada** sirve; bórrala o ignórala en producción |
| Funciones Lambda que solo llaman servicios públicos de AWS | No necesitan VPC (si la usas, añade endpoints o NAT) |
| Necesitas aislar entornos | **Cuentas** distintas, no solo VPC distintas |

> Una VPC **no es un límite de seguridad suficiente por sí sola**: el límite fuerte es la cuenta; dentro, grupos de seguridad y roles.

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **CIDR** | Notación `10.20.0.0/16`: dirección base y cuántos bits son «red» |
| **Subred pública/privada** | Con o sin ruta al IGW |
| **Salto (target)** | A dónde apunta una ruta (IGW, NAT, TGW, peering, endpoint) |
| **ENI** | Interfaz de red virtual; casi todo se conecta a la VPC por una |
| **DNS de VPC** | Resolutor en la base +2; requiere `enableDnsSupport` |
| **Nombres de host DNS** | `enableDnsHostnames` da nombres públicos a las instancias; **necesario para endpoints de interfaz con DNS privado** |
| **Zona local / borde** | Extensiones fuera de la región |

## 5. Cómo se usa

1. Planifica el bloque (hoja central) y las AZ.
2. Crea con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) (VPC, tres niveles de subredes, IGW, un NAT por AZ, tablas de rutas, registros de flujo opcionales).
3. Verifica con la CLI: [`ejemplos/cli/vpc.sh`](ejemplos/cli/vpc.sh).
4. Activa **Flow Logs** y guarda consultas útiles: [`consultas.md`](ejemplos/logs-insights/consultas.md).
5. Continúa con [grupos de seguridad y rutas](../sg-nacl-rutas-nat/README.md) y [endpoints](../vpc-endpoints-privatelink/README.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | `ec2:*Vpc*`, `ec2:*Subnet*`, `ec2:*RouteTable*`, NAT/IGW acotado por etiqueta | — |
| Equipo de aplicaciones | `ec2:Describe*` (solo lectura) | Lo de sus servicios |
| Seguridad/auditoría | `ec2:Describe*` + Flow Logs | Leer registros en S3/CloudWatch |

- **Menos IP públicas**: solo balanceadores y NAT; todo lo demás privado.
- **Block Public Access** para S3 y **grupos de seguridad** estrictos (siguiente servicio).
- **Flow Logs** activos y enviados a la cuenta de registros.
- Evita la VPC predeterminada en producción (subredes públicas por defecto).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Tres AZ con un NAT por AZ en producción | Un solo NAT para todo (si cae su AZ, todos pierden salida) |
| Subredes de aplicación grandes (`/22`) | `/28` para un clúster de contenedores |
| Datos sin ruta a internet | Bases de datos en subredes públicas |
| Registros de flujo desde el día 1 | Habilitarlos «cuando haya un problema» |
| Endpoints para S3/DynamoDB (gratis) | Mandar tráfico de S3 por el NAT y pagar por GB |
| Bloques planificados y centralizados | Cada equipo elige `10.0.0.0/16` |

## 8. Límites, costos y versiones
- **Costo:** la VPC y las subredes no cuestan; **sí** el NAT Gateway (por hora **y por GB**), las IPv4 públicas (por hora) y los registros de flujo (ingesta/almacenamiento). *Verifica precios y regiones.*
- **Límites típicos** (ajustables, verifica la cuota vigente): VPC por región, subredes por VPC, reglas por tabla de rutas, IP elásticas por región.
- **Terraform:** proveedor `aws` 6.x; ejemplos validados con `init` + `validate`. Java 21, SDK v2 (BOM 2.56).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
