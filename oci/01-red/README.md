# Oracle OCI · 01 Red

Casi todo error «raro» en la nube es de DNS, red o permisos. Este capítulo reúne las cinco piezas de red de OCI: cada una responde una pregunta distinta.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [VCN y subredes](vcn-subredes/README.md) | ¿Cuál es **mi red** y cómo la divido? | Un barrio cerrado con calles | Toda carga: rangos, subredes públicas/privadas, gateways |
| [Listas de seguridad, NSG y rutas](seguridad-rutas-gateways/README.md) | ¿**Quién puede hablar con quién** y por dónde sale? | Reglamento de calle + llave de casa + letreros | Controlar tráfico entre capas |
| [DRG, peering e híbrido](drg-peering/README.md) | ¿Cómo **conecto** varias redes y mi oficina? | Estación central de trenes | Hub-and-spoke, VPN, FastConnect |
| [Service Gateway, endpoints y DNS privado](endpoints-privados-dns/README.md) | ¿Cómo hablo con servicios de Oracle **sin Internet** y con nombres internos? | Pasillo al ayuntamiento + guía telefónica | Object Storage, bases privadas, DNS híbrido |
| [Diagnóstico de conectividad](diagnostico-conectividad/README.md) | ¿**Por qué no conecta**? | Buscar una carta perdida | La escalera DNS → ruta → seguridad → puerto → TLS → identidad |

## Árbol de decisión: «quiero…»

```
¿Quiero una red para una aplicación?
   └─ VCN con 3 subredes (lb pública; app y datos privadas)

¿Quiero que solo el balanceador reciba Internet?
   └─ Subred pública solo para él; NSG por rol en el resto

¿Quiero que mis pods suban a Object Storage sin salir a Internet?
   └─ Service Gateway + ruta al CIDR del servicio

¿Quiero conectar dev, prod y mi oficina?
   └─ DRG con hub-and-spoke (tablas de rutas por rol), VPN IPSec o FastConnect

¿Quiero nombres internos (pedidos-db.interno)?
   └─ Vista privada de DNS asociada al resolutor de la VCN

¿No conecta?
   └─ La escalera: DNS → ruta → seguridad → puerto → TLS → identidad
```

## Comparativa

| Característica | Lista de seguridad | NSG | Tabla de rutas | DRG |
|---|---|---|---|---|
| Se aplica a | Subred | VNIC | Subred | VCN adjuntas, VPN, circuitos |
| Decide | Permitir tráfico | Permitir tráfico (por rol) | Siguiente salto | Enrutamiento entre redes |
| Referencia a otro grupo | No | **Sí** | — | — |
| Costo | Gratis | Gratis | Gratis | Gratis (tráfico y enlaces se cobran) |
| Error típico | Reglas abiertas olvidadas | NSG sin asignar | Falta ruta de vuelta | Tablas compartidas entre dev y prod |

## La receta ModaLima

| Pieza | Diseño |
|---|---|
| VCN prod | `10.30.0.0/16` en `sa-saopaulo-1`, subredes `lb` (pública), `app` y `datos` (privadas) |
| Salidas | NAT para Internet, Service Gateway para Object Storage y Vault |
| Reglas | NSG `lb` → `app` (8080) → `datos` (5432); lista mínima con ICMP de MTU |
| Conexión | DRG con hub (firewall, DNS, bastión) y spokes prod/dev; VPN con dos túneles a la oficina |
| DNS | Vista privada `prod.tienda.interno`; reenvío a `corp.interno` |
| Operación | Registros de flujo en `lb`/`app`; escalera de diagnóstico en el runbook |

## Orden recomendado de adopción
1. **Plan de CIDR** de toda la empresa.
2. **VCN y subredes**, gateways y rutas (Terraform).
3. **NSG por rol** y lista mínima.
4. **Service Gateway** en cada subred privada.
5. **DRG** cuando aparezca la segunda red o la oficina.
6. **DNS privado** cuando hay endpoints privados u on-premises.
7. **Registros de flujo** y la escalera en el runbook.

## Reglas transversales
- Privado por defecto; público solo lo imprescindible.
- Mínimo privilegio de red: puertos y orígenes concretos.
- Ningún CIDR repetido en la empresa.
- Todo como código; sin cambios manuales en producción.
- Probar desde el lugar donde corre la aplicación.
- La red privada **no** reemplaza IAM.

## Java en red: qué construye cada `uso-en-java.md`

| Unidad | Qué construyes | Patrón común |
|---|---|---|
| VCN y subredes | Planificador de subredes (3 IP reservadas, alineación) e inventario idempotente | Núcleo puro + SDK |
| Seguridad y rutas | Auditor de reglas (admin/datos abiertos, sin estado) | «No se pudo leer» es hallazgo |
| DRG | Verificador de CIDR solapados contra VCN reales y on-premises | Informa; no conecta |
| Endpoints y DNS | Comprobador de resolución desde el pod y cruce con la zona | Probar donde corre la app |
| Diagnóstico | Escalera DNS/TCP/TLS y analizador de rutas (prefijo más largo) | Detenerse en el primer fallo |

Reglas comunes: autenticación según dónde corre (config, instance, oke, resource), cierre de clientes, nunca bloquear el bucle de eventos.

## Cómo se relaciona con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): compartimentos, regiones y AD.
- [IAM](../02-iam/README.md): políticas y grupos dinámicos que permiten a la aplicación usar la red.
- [Compute](../04-compute/README.md): VNIC, nodos de OKE y funciones viven en estas subredes.
- [Ingress y API](../05-ingress-api/README.md): balanceadores en la subred pública.
- [Gobierno](../09-gobierno/README.md): auditoría de cambios de red.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
