# Google Cloud · 00 Fundamentos

Antes de crear un solo recurso conviene entender cómo organiza Google Cloud todo: **organización → carpetas → proyectos → recursos**, dónde viven (regiones y zonas), quién paga (cuentas de facturación) y cómo se autentica tu código (ADC y cuentas de servicio).

## 1. Qué es Google Cloud (con analogía)

**Analogía:** un centro comercial. La **organización** es el dueño del edificio; las **carpetas** son pisos por área; cada **proyecto** es un local con su propia caja registradora (facturación), sus empleados (IAM) y sus servicios encendidos (APIs). Lo que pasa en un local no afecta a otro salvo que lo conectes.

```
 Organización (modalima.example)  ── políticas de organización, IAM heredado
   ├─ Carpeta "plataforma"   └─ proyecto red-compartida (Shared VPC host)
   ├─ Carpeta "tienda"
   │    ├─ proyecto modalima-tienda-prod     ← cuenta de facturación, APIs, IAM, recursos
   │    └─ proyecto modalima-tienda-noprod
   └─ Carpeta "sandbox" (cuotas y presupuesto bajos)
```

## 2. Cómo funciona por dentro

### Jerarquía y recursos
| Nivel | Qué es | Detalle clave |
|---|---|---|
| **Organización** | Raíz ligada a un dominio (Cloud Identity/Workspace) | Políticas de organización y roles globales |
| **Carpeta** | Agrupa proyectos (hasta 10 niveles *(verifica)*) | IAM y políticas se heredan hacia abajo |
| **Proyecto** | Unidad de facturación, cuotas, APIs e IAM | Tiene **ID** (único, inmutable), **nombre** y **número** |
| **Recurso** | VM, bucket, tema de Pub/Sub… | Nombre completo: `projects/<id>/locations/<región>/…` |

### Regiones y alcance de los servicios
| Alcance | Ejemplos |
|---|---|
| **Global** | Redes VPC, balanceadores HTTPS globales, IAM, Pub/Sub (temas) |
| **Regional** | Subredes, Cloud Run, Cloud SQL, GKE regional, buckets regionales |
| **Zonal** | VMs de Compute Engine, discos persistentes zonales, GKE zonal |
| **Multirregional** | Buckets `US`/`EU`, Spanner multirregional, BigQuery `US`/`EU` |

Una región tiene 3 o más zonas *(verifica por región)*; para alta disponibilidad, reparte entre zonas.

### Modelos de servicio con nombres de Google Cloud
| Modelo | Servicios |
|---|---|
| IaaS | Compute Engine, discos, VPC |
| Contenedores | GKE (Standard y Autopilot), Cloud Run |
| Sin servidores | Cloud Run functions, Pub/Sub, Eventarc, Cloud Tasks |
| Datos administrados | Cloud SQL, AlloyDB, Spanner, Firestore, Bigtable, Memorystore, BigQuery |

## 3. Responsabilidad compartida
| Google | Tú |
|---|---|
| Centros de datos, hardware, red global, hipervisor | IAM, cuentas de servicio, reglas de firewall |
| Parches de servicios administrados | Configuración de cada servicio, datos, cifrado con tus llaves si aplica |
| Disponibilidad de la plataforma | Diseño multizona/multirregión de tu aplicación |

## 4. Cómo se habla con Google Cloud
- **Consola**, **`gcloud`** (CLI), **Terraform** (`hashicorp/google`), **bibliotecas cliente** (Java) y APIs REST/gRPC.
- Cada servicio es una **API** que hay que **habilitar** en el proyecto (`gcloud services enable run.googleapis.com`).
- Las llamadas se autorizan con **IAM**: principal (usuario, grupo, cuenta de servicio) + rol + recurso.

### Cómo el código Java decide sus credenciales (ADC)
Las bibliotecas buscan **Application Default Credentials** en este orden *(verifica)*:
1. Variable `GOOGLE_APPLICATION_CREDENTIALS` (archivo de credenciales; **evita llaves JSON**).
2. Credenciales de `gcloud auth application-default login` (tu laptop).
3. El **servidor de metadatos**: la cuenta de servicio adjunta a la VM, al pod de GKE (Workload Identity), a Cloud Run o a la función.

En producción, siempre la opción 3: sin archivos de llaves. Para actuar como otra cuenta, **suplantación** (`roles/iam.serviceAccountTokenCreator`).

## 5. Costos
- Pago por uso con **descuentos por uso continuo** (Compute Engine) y **compromisos** (CUD) *(verifica)*.
- **Nivel gratuito** permanente en varios servicios con límites *(verifica)*.
- Facturación por **cuenta de facturación** asociada a proyectos; exporta a **BigQuery** para analizar.
- Presupuestos con alertas (no detienen el gasto por sí solos).

## 6. Etiquetas y nombres
| Mecanismo | Para qué |
|---|---|
| **Labels** (`clave=valor` en recursos) | Costos y organización; aparecen en la exportación de facturación |
| **Tags** (recursos de la organización) | Condiciones de IAM y políticas de firewall/organización |
| **Convención de IDs de proyecto** | `<empresa>-<producto>-<entorno>` (no se puede cambiar después) |

## 7. Seguridad básica desde el día 1
- Nadie con `roles/owner` en producción; grupos, no usuarios sueltos.
- **Políticas de organización**: bloquear llaves de cuentas de servicio, IP públicas en VMs, recursos fuera de regiones permitidas.
- Una **cuenta de servicio por aplicación**, con roles mínimos.
- Audit Logs activados (los de administración vienen siempre activos).
- Presupuestos con alertas en cada proyecto.

## 8. Caso inventado: ModaLima en Google Cloud
| Necesidad | Decisión |
|---|---|
| Separar equipos y entornos | Carpetas por área, proyectos por producto y entorno |
| Red común | Shared VPC en `red-compartida` |
| Microservicios | Cloud Run para APIs simples, GKE Autopilot para la plataforma |
| Pedidos | Cloud SQL (PostgreSQL) con conexión privada |
| Eventos | Pub/Sub |
| Secretos | Secret Manager |
| Costos | Labels `centro_costo`, exportación a BigQuery, presupuestos por proyecto |

## 9. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Un proyecto por producto y entorno | Un proyecto gigante para todo |
| ADC con cuenta de servicio adjunta | Archivos de llave JSON en imágenes |
| Habilitar solo las APIs necesarias | Habilitar todo «por si acaso» |
| Políticas de organización desde el inicio | Agregarlas después del incidente |
| Labels obligatorias | Gasto imposible de asignar |

## 10. Glosario
| Término | En simple |
|---|---|
| **ID de proyecto** | Nombre único global del proyecto |
| **Número de proyecto** | Identificador numérico (aparece en cuentas de servicio por defecto) |
| **Principal** | Quién: usuario, grupo, cuenta de servicio |
| **Rol** | Conjunto de permisos (`roles/storage.objectViewer`) |
| **Cuenta de servicio** | Identidad de una aplicación |
| **ADC** | Forma estándar en que el código encuentra credenciales |
| **Servidor de metadatos** | Servicio local que entrega tokens a VMs, pods y servicios |
| **Shared VPC** | Una red de un proyecto host usada por proyectos de servicio |

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [01 Red](../01-red/README.md)
