# Oracle OCI · Red · Service Gateway, endpoints privados y DNS privado

Tus microservicios deben hablar con servicios de Oracle (Object Storage, bases de datos, Vault, Streaming) **sin salir a Internet**. En OCI eso se logra con el **Service Gateway** (para los servicios de Oracle en general) y con **endpoints privados** (para servicios que los ofrecen), y se completa con **DNS privado** para que los nombres resuelvan a direcciones internas.

## 1. Qué es

**Analogía:** el barrio tiene un **pasillo cubierto hacia el ayuntamiento** (Service Gateway): para trámites municipales no sales a la calle. Algunas oficinas (una base de datos, un vault) además instalan **una ventanilla dentro de tu barrio** (endpoint privado): tiene una dirección interna tuya. Y la **guía telefónica interna** (DNS privado) hace que «`pedidos-db`» apunte a esa ventanilla, no a la oficina pública.

```
 Pod en subred app ─DNS─► pedidos-db.tienda.interno ─► 10.30.20.15 (endpoint privado en subred datos)
        │
        └─► objectstorage.sa-saopaulo-1.oraclecloud.com ─► Service Gateway ─► Object Storage (sin Internet)
```

## 2. Cómo funciona por dentro

### Dos mecanismos
| | Service Gateway | Endpoint privado |
|---|---|---|
| Alcance | Muchos servicios de Oracle a la vez (CIDR «todos los servicios») | Un recurso concreto (una base, un vault, un API Gateway privado) |
| Dirección | IP **pública** de Oracle, pero el tráfico va por la red interna de Oracle | **IP privada de tu subred** |
| Control | Ruta + reglas de seguridad con CIDR de servicio | NSG propio del endpoint |
| Ejemplo | Object Storage, Logging, Monitoring | Autonomous Database privada, OKE (API privada), Streaming |

> Qué servicios admiten endpoint privado cambia con el tiempo: **verifica en la documentación de cada servicio**.

### Cómo se conecta el Service Gateway
1. Se crea el **gateway** en la VCN asociado a «All <región> Services in Oracle Services Network» (o solo Object Storage).
2. En la **tabla de rutas** de la subred: destino = CIDR del servicio (`SERVICE_CIDR_BLOCK`), siguiente salto = el gateway.
3. Las **reglas de seguridad** permiten salida hacia el CIDR del servicio.

### DNS en OCI
| Pieza | Qué hace |
|---|---|
| **Resolutor de la VCN** | Servidor DNS por defecto (169.254.169.254) |
| **Vista privada (*view*)** | Conjunto de zonas privadas visible solo para las VCN a las que se asocia |
| **Zona privada** | Dominio interno (`tienda.interno`) con sus registros |
| **Endpoint de escucha** | Permite que redes externas (on-premises) consulten tus zonas privadas |
| **Endpoint de reenvío + reglas** | Envía consultas de ciertos dominios a un DNS externo (on-premises) |
| **Nombres internos de VCN** | `host.subred.vcn.oraclevcn.com`, si la VCN y la subred tienen *dns label* |

### Nombres que debes usar
Con un endpoint privado, usa **el nombre que el servicio documenta** (FQDN) y que resuelva, vía vista privada o DNS del servicio, a la IP privada. Si resuelve a una IP pública, el endpoint no está en uso.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Subir archivos a Object Storage desde una subred privada | Service Gateway |
| Base de datos solo accesible desde la VCN | Endpoint privado + NSG |
| Resolver nombres internos entre VCN y on-premises | Vista privada + endpoints de DNS |
| Salir a Internet para hablar con Object Storage | **No**: cuesta y expone |
| IP fijas escritas en el código | **No**: usa nombres |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Service Gateway** | Pasillo privado hacia servicios de Oracle |
| **Endpoint privado** | IP interna de tu VCN para un servicio |
| **CIDR de servicio** | Rango que representa a los servicios de Oracle |
| **Vista privada** | Guía telefónica interna asociada a una VCN |
| **Resolutor** | Servidor DNS de la VCN |
| **Endpoint de reenvío** | Pregunta a un DNS externo por ciertos dominios |

## 5. Cómo se usa
1. Service Gateway y ruta ([VCN](../vcn-subredes/README.md)).
2. Vista y zona privadas, y registros: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Comprueba la resolución **desde el pod**: [`ejemplos/cli/dns.sh`](ejemplos/cli/dns.sh) y el comprobador en [Java](uso-en-java.md).
4. Reglas de seguridad: el NSG del endpoint admite solo el NSG de la aplicación.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red | `manage dns`, `manage service-gateways`, `manage private-ips` | — |
| Aplicación | — | Acceso al servicio con su propio principal; la red privada **no** reemplaza los permisos |
| Auditoría | `inspect dns`, Audit | Registros de consultas DNS (opcional) |

- La red privada reduce exposición, pero **IAM sigue siendo obligatorio**.
- Una vista privada compartida entre VCN mezcla nombres: separa por entorno.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Service Gateway en toda subred que hable con servicios de Oracle | Salir por NAT hacia Object Storage |
| Nombres, no IP | IP fijas en configuración |
| Comprobar la resolución desde el pod | Suponer que si resuelve en tu laptop resuelve en el pod |
| NSG propio del endpoint | Endpoint abierto a toda la VCN |
| Vistas por entorno | Una vista para todo |

## 8. Límites, costos y versiones
- **Costo:** el Service Gateway no se cobra; los endpoints privados dependen del servicio; DNS privado tiene tarifa por consultas y zonas. *(verifica)*
- **Terraform:** `oci_dns_view`, `oci_dns_zone` (`scope = "PRIVATE"`), `oci_dns_rrset`, `oci_dns_resolver`, `oci_dns_resolver_endpoint`, `oci_core_service_gateway`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
