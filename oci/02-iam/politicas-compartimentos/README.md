# Oracle OCI · IAM · Compartimentos, grupos y políticas

En OCI **nada se puede hacer sin una política que lo permita**. Las políticas son frases legibles («permite al grupo X hacer Y sobre Z en el compartimento W») y, junto con los **compartimentos**, forman el corazón de la seguridad del tenancy.

## 1. Qué es

**Analogía:** el edificio de oficinas ([tenancy](../../00-fundamentos/README.md)) tiene **departamentos** (compartimentos) y un **libro de autorizaciones** (políticas). Cada autorización dice: «el grupo *contabilidad* puede **ver** los archivos del departamento *finanzas*». Lo que no está escrito, **está prohibido**: no existe una regla de «denegar».

```
Allow group <quién> to <verbo> <tipo-de-recurso> in compartment <dónde> [where <condición>]
       │                │            │                   │                   │
   grupo o       inspect < read   familia de        compartimento        filtro fino
   grupo dinámico  < use < manage  recursos         (o tenancy)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Compartimento** | Carpeta de recursos, anidable; las políticas se heredan hacia los hijos |
| **Grupo** | Conjunto de usuarios |
| **Grupo dinámico** | Conjunto de **recursos** (instancias, funciones…) que actúan como identidad ([unidad](../dynamic-groups-principals/README.md)) |
| **Política** | Lista de frases (*statements*) adjunta a un compartimento (o al tenancy) |
| **Verbo** | `inspect` (listar) < `read` (leer contenido) < `use` (operar) < `manage` (todo, incluye crear y borrar) |
| **Tipo de recurso** | Individual (`buckets`, `instances`) o **familia** (`object-family`, `virtual-network-family`, `all-resources`) |
| **Condición** | `where` sobre atributos de la petición o del recurso |

### Cómo se evalúa
1. Todo está **denegado** por defecto.
2. Se **suman** las frases que apliquen: si alguna lo permite, se permite.
3. Una política adjunta a un compartimento aplica a **ese compartimento y sus hijos**.
4. El alcance mínimo de una política es el compartimento donde se adjunta: para dar permisos en `tienda/prod` desde `tienda`, la política puede vivir en `tienda`.

### Ejemplos de frases
| Frase | Significado |
|---|---|
| `Allow group Desarrollo to read all-resources in compartment tienda-dev` | Lectura general en dev |
| `Allow group Desarrollo to manage instance-family in compartment tienda-dev` | Todo con VM en dev |
| `Allow group Redes to manage virtual-network-family in compartment red` | Equipo de red |
| `Allow group Auditores to inspect all-resources in tenancy` | Listar recursos en todo el tenancy |
| `Allow dynamic-group app-tienda to read objects in compartment tienda-prod where target.bucket.name = 'comprobantes'` | La aplicación lee objetos de **un** bucket |

### Condiciones frecuentes
| Condición | Para qué |
|---|---|
| `target.bucket.name = 'x'` | Limitar a un bucket |
| `target.compartment.name = 'x'` | Limitar al compartimento destino |
| `request.principal.type = 'workload'` | Solo cargas de OKE ([unidad](../workload-identity-oke/README.md)) |
| `request.user.id`, `request.region` | Quién y desde dónde |
| `target.resource.tag.<ns>.<clave> = 'valor'` | Por etiqueta |

### Diseño de compartimentos
```
raiz (tenancy)
 ├─ plataforma      (red, seguridad, registros, vault)
 ├─ tienda
 │    ├─ tienda-prod
 │    └─ tienda-dev
 └─ sandbox
```
Una política por equipo y compartimento, **no** una política gigante: es más fácil de revisar.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Dar acceso a un equipo a su entorno | Grupo + política en el compartimento |
| Permisos de una aplicación | Grupo dinámico + política mínima |
| Excepciones puntuales | Condición `where` |
| `manage all-resources in tenancy` para un equipo | **No** (solo el grupo administrador) |
| `any-user` sin condiciones | **No** |
| Copiar una política de otro tenancy sin entenderla | **No** |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Statement** | Una frase de la política |
| **Verbo** | Nivel de poder: `inspect`, `read`, `use`, `manage` |
| **Familia de recursos** | Conjunto de tipos relacionados (`object-family`) |
| **Herencia** | Lo permitido en un compartimento vale en sus hijos |
| **Denegación implícita** | Lo no escrito está prohibido |
| **any-user** | Cualquier principal (peligroso sin condición) |

## 5. Cómo se usa
1. Diseña compartimentos y grupos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Escribe políticas **mínimas**: [`ejemplos/json/frases.json`](ejemplos/json/frases.json).
3. Revisa con el linter de [Java](uso-en-java.md) antes de aplicar.
4. Opera con [`ejemplos/cli/politicas.sh`](ejemplos/cli/politicas.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores del tenancy | Grupo `Administrators` (muy pocos, con MFA) | — |
| Administradores de compartimento | `manage` limitado a su compartimento | Según rol |
| Aplicaciones | Grupos dinámicos y principales | Solo los recursos que usan |

- **Separa** quien administra identidad de quien administra recursos.
- **Audita** los cambios de políticas ([Audit](../../09-gobierno/README.md)).
- **Prueba** en `sandbox` antes de aplicar en producción.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Políticas pequeñas por equipo y compartimento | Una política enorme |
| `read`/`use` antes que `manage` | `manage all-resources` por comodidad |
| Condiciones `where` para acotar | `any-user` sin condiciones |
| Todo como código | Editar políticas en la consola |
| Revisar con un linter | Revisar a ojo |

## 8. Límites, costos y versiones
- **Costo:** IAM es gratuito.
- **Límites** (verifica): frases por política, políticas por compartimento, grupos por tenancy.
- **Terraform:** `oci_identity_compartment`, `oci_identity_group` (o `oci_identity_domains_group`), `oci_identity_policy`.
- Con **identity domains**, el grupo se nombra con su dominio: `'Default'/'Desarrollo'` *(verifica la sintaxis vigente)*.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
