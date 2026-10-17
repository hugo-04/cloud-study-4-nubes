# Oracle OCI · 00 Fundamentos

Todo lo que necesitas entender de Oracle Cloud Infrastructure (OCI) **antes** de tocar un servicio: cómo se organizan el tenancy y los compartimentos, dónde viven los recursos, cómo se habla con la nube y cómo se controlan permisos y costos.

## 1. Qué es OCI (con analogía)

**OCI es un edificio de oficinas con administración central.** Tu empresa alquila **un piso entero (el *tenancy*)**; dentro del piso creas **departamentos (compartimentos)** con puertas y llaves propias; la administración (Oracle) mantiene el edificio —energía, ascensores, seguridad física— y tú decides quién entra a cada departamento y qué muebles pones.

```
Tenancy (tu cuenta de nube: un OCID)
 ├─ Compartimento raíz (el propio tenancy)
 │    ├─ Compartimento plataforma     ── red central, vault, registros
 │    ├─ Compartimento tienda-prod    ── VCN, OKE, base de datos de producción
 │    ├─ Compartimento tienda-dev     ── lo mismo, más pequeño
 │    └─ Compartimento sandbox        ── laboratorio con cuotas bajas
 └─ Regiones suscritas (home region + otras)
```

## 2. Cómo funciona por dentro

### Jerarquía y recursos
| Concepto | Qué es | Para qué |
|---|---|---|
| **Tenancy** | La cuenta raíz de tu empresa; tiene un OCID, una región *home* y un administrador inicial | Frontera de facturación, identidad y límites |
| **Compartimento** | Contenedor lógico de recursos, **anidable hasta 6 niveles** | Aislar por equipo/entorno y aplicar permisos, cuotas y presupuestos |
| **OCID** | Identificador único de cualquier recurso: `ocid1.<tipo>.<realm>.<región>.<id>` | Referenciar recursos en políticas, API y Terraform |
| **Región** | Ubicación geográfica con varios centros de datos (ej. `us-ashburn-1`, `sa-saopaulo-1`, `sa-santiago-1`) | Dónde corre tu carga |
| **Dominio de disponibilidad (AD)** | Un centro de datos dentro de una región (algunas regiones tienen 1, otras 3) | Alta disponibilidad entre centros |
| **Dominio de fallas (FD)** | Tres grupos de hardware independientes dentro de cada AD | Alta disponibilidad dentro de un AD |
| **Realm** | Conjunto aislado de regiones (comercial `oc1`, gobierno, soberana…) | Cumplimiento y aislamiento |

Los compartimentos son **globales al tenancy** (se ven desde todas las regiones); los recursos, en cambio, **viven en una región** (y varios en un AD concreto).

### Regiones y alcance de los servicios
| Alcance | Ejemplos | Qué implica |
|---|---|---|
| **Global (tenancy)** | Compartimentos, políticas, grupos, dominios de identidad, etiquetas | Se crean una vez, en la región *home* |
| **Regional** | VCN, buckets de Object Storage, OKE, balanceadores, bases de datos, colas | Existen en una región; para otra región se crea otro |
| **Por AD** | Instancias de cómputo, volúmenes de bloque, sistemas de archivos, subredes (si se atan a un AD) | Eliges el AD; prefiere subredes regionales |

> La **región *home*** es donde se crean los recursos de identidad. Elígela con cuidado: **no se puede cambiar**. *(verifica)*

### Modelos de servicio con nombres de OCI
| Modelo | Ejemplos en OCI | Tú administras |
|---|---|---|
| **IaaS** | Compute (VM, bare metal), Block Volume, VCN | Sistema operativo, parches, runtime |
| **CaaS** | Container Instances, OKE (Kubernetes Engine) | Imágenes, manifiestos, configuración |
| **PaaS / gestionado** | Autonomous Database, MySQL HeatWave, PostgreSQL, Queue, Streaming, API Gateway | Datos, esquema, permisos |
| **FaaS** | OCI Functions (basado en Fn Project) | Código y su configuración |

## 3. Responsabilidad compartida

| Capa | Oracle | Tú |
|---|---|---|
| Instalaciones, hardware, red física, hipervisor | ✅ | |
| Servicios gestionados (parches del motor, copias base) | ✅ | |
| Identidad, políticas, grupos | | ✅ |
| Configuración de red (listas de seguridad, NSG, rutas) | | ✅ |
| Sistema operativo de tus VM y nodos | | ✅ (en VM); ✅ parcial en nodos gestionados |
| Datos, cifrado con tus claves, clasificación | | ✅ |
| Cumplimiento de tu aplicación | | ✅ |

## 4. Cómo se habla con OCI

| Herramienta | Para qué | Autenticación típica |
|---|---|---|
| **Consola web** | Explorar, aprender | Usuario con MFA |
| **Cloud Shell** | Terminal en el navegador con la CLI ya autenticada | Tu sesión |
| **OCI CLI** (`oci`) | Automatizar y operar | Archivo `~/.oci/config` con clave de API, o *session token*, o *instance principal* |
| **SDK de Java** | Aplicaciones | Ver abajo |
| **Terraform / OpenTofu** (`oracle/oci`) | Infraestructura como código | Clave de API en local; *instance principal* o *resource principal* en pipelines |
| **Resource Manager** | Terraform administrado por OCI | Principal del servicio |

### Cómo el SDK de Java decide sus credenciales
No hay una cadena automática como en otras nubes: **eliges el proveedor de autenticación**.

| Proveedor | Cuándo | Clase |
|---|---|---|
| Archivo de configuración | Desarrollo local (`~/.oci/config`) | `ConfigFileAuthenticationDetailsProvider` |
| **Instance principal** | Código en una VM de OCI (grupo dinámico) | `InstancePrincipalsAuthenticationDetailsProvider` |
| **Resource principal** | Código en OCI Functions | `ResourcePrincipalAuthenticationDetailsProvider` |
| **Workload identity de OKE** | Pods en OKE (cuenta de servicio) | `OkeWorkloadIdentityAuthenticationDetailsProvider` (artefacto adicional `oci-java-sdk-addons-oke-workload-identity`) |
| Token de sesión | CLI/SDK con `oci session authenticate` | `SessionTokenAuthenticationDetailsProvider` |

Regla: **local = archivo de configuración; en OCI = principales (nunca claves en la imagen)**.

## 5. Costos

- **Pago por uso** (*Pay As You Go*) o **Universal Credits** (compromiso anual con descuento). Facturación por segundo en cómputo. *(verifica)*
- **Always Free:** un conjunto de recursos gratuitos de por vida (VM pequeñas ARM/AMD, base Autonomous, almacenamiento limitado). *(verifica límites vigentes)*
- **Salida de datos (egress):** los primeros GB al mes suelen ser gratuitos y luego se cobra por GB; entre regiones y hacia Internet. *(verifica)*
- Controla el gasto con **presupuestos** por compartimento, **etiquetas de costo** y **cuotas** ([Gobierno](../09-gobierno/README.md)).

## 6. Etiquetas y nombres

| Tipo | Qué es | Ejemplo |
|---|---|---|
| **Etiqueta libre** (*freeform tag*) | Par clave/valor sin esquema | `entorno=prod` |
| **Etiqueta definida** (*defined tag*) | Pertenece a un *namespace* con claves y valores controlados | `Costos.centro = CC-2210` |
| **Nombre** | Convención propia | `prod-tienda-vcn`, `prod-tienda-pedidos-db` |

Los nombres de compartimento son únicos entre hermanos; los demás recursos no exigen unicidad global (el OCID sí es único). Usa **etiquetas definidas** para costos y propiedad: se pueden forzar con *valores por defecto* de etiquetas del compartimento.

## 7. Seguridad básica desde el día 1

1. **Nunca uses el usuario administrador del tenancy** en el día a día: crea grupos y políticas mínimas.
2. **MFA** para todos los humanos (dominio de identidad).
3. **Compartimentos por entorno y equipo**; permisos al nivel del compartimento, no del tenancy.
4. **Sin claves de API en repositorios**; en OCI usa principales (instancia, recurso, workload).
5. **Cloud Guard y Security Zones** activos ([Gobierno](../09-gobierno/README.md)).
6. **Registro de auditoría** (Audit) siempre disponible; envíalo a Object Storage si necesitas más retención.
7. **Presupuesto con alerta** el primer día.

## 8. Caso inventado: ModaLima en OCI

ModaLima vende ropa en línea y migra su tienda a OCI. Define: tenancy con compartimentos `plataforma`, `tienda-prod`, `tienda-dev` y `sandbox`; región *home* `us-ashburn-1` y carga en `sa-saopaulo-1`; presupuesto mensual por compartimento; pipelines con *resource principal*. **Café Andino**, su cliente mayorista, consume sus eventos de inventario por Streaming (compatible con Kafka).

## 9. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Compartimentos por entorno/equipo | Todo en el compartimento raíz |
| Grupos + políticas mínimas, con MFA | Usar el usuario inicial para todo |
| Principales (instancia/recurso/workload) | Claves de API dentro de imágenes o repositorios |
| Etiquetas definidas de costo | Nombres como única forma de identificar dueño |
| Presupuesto y cuotas desde el inicio | Descubrir el gasto en la factura |
| Todo como código | Clics manuales en producción |
| Elegir con cuidado la región *home* | Asumir que se puede cambiar |

## 10. Glosario

| Término | En simple |
|---|---|
| **Tenancy** | Tu cuenta raíz en OCI |
| **Compartimento** | Carpeta de recursos con permisos propios |
| **OCID** | Identificador único de un recurso |
| **Región / AD / FD** | Zona geográfica / centro de datos / grupo de hardware independiente |
| **Home region** | Región donde viven los recursos de identidad |
| **Política (policy)** | Regla de texto que da permisos a grupos |
| **Grupo dinámico** | Conjunto de recursos (instancias, funciones) que actúan como identidad |
| **Principal** | Quien hace una llamada: usuario, instancia, función, pod |
| **Etiqueta definida** | Etiqueta con esquema controlado |
| **Cuota (quota)** | Techo de recursos por compartimento |
| **Límite de servicio** | Tope por tenancy/región que se puede ampliar solicitándolo |

**Siguiente capítulo:** [Red](../01-red/README.md)
