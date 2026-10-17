# Oracle OCI · IAM · Grupos dinámicos y principales (instancias y funciones)

Tu código también necesita identidad. En OCI, en vez de guardar llaves en la máquina, **la máquina misma es la identidad**: una VM, una función o un pod pertenece a un **grupo dinámico**, y la política le da permisos a ese grupo.

## 1. Qué es

**Analogía:** el uniforme de una empresa. No le das a cada empleado una llave maestra: quien lleve el uniforme del área «cocina» entra a la cocina. El grupo dinámico es la regla que decide **quién lleva el uniforme** (por ejemplo, «todas las VM del compartimento tienda-prod»).

```
VM / Función ──(tokens firmados por OCI)──► IAM
        │                                     │
   ¿coincide con la regla del grupo dinámico? │
        └────────────► Allow dynamic-group app-tienda to read objects in compartment …
```

## 2. Cómo funciona por dentro

### Tipos de principal
| Principal | Quién es | Cómo se obtiene en Java |
|---|---|---|
| **Instance principal** | Una VM | `InstancePrincipalsAuthenticationDetailsProvider` |
| **Resource principal** | Una función de OCI Functions u otro servicio | `ResourcePrincipalAuthenticationDetailsProvider` |
| **Workload identity** | Un pod en OKE | `OkeWorkloadIdentityAuthenticationDetailsProvider` ([unidad](../workload-identity-oke/README.md)) |
| **Usuario** | Una persona | Archivo de configuración o sesión |

### Regla de coincidencia (*matching rule*)
```
ALL {instance.compartment.id = 'ocid1.compartment.oc1..aaaa', tag.app.nombre.value = 'tienda'}
ANY {resource.type = 'fnfunc', resource.compartment.id = 'ocid1.compartment.oc1..bbbb'}
```
- `ALL { … }` = todas las condiciones. `ANY { … }` = al menos una.
- Atributos habituales: `instance.id`, `instance.compartment.id`, `resource.type`, `resource.compartment.id`, `tag.<ns>.<clave>.value`.

### Cómo se obtiene el token
1. La VM pide sus credenciales al **servicio de metadatos** local (`169.254.169.254`).
2. OCI emite un certificado y un token **de vida corta**, que el SDK renueva solo.
3. IAM evalúa: ¿la VM coincide con algún grupo dinámico? ¿Qué políticas citan ese grupo?

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| App en VM que lee un bucket | Grupo dinámico + política mínima |
| Función que escribe en una cola | Resource principal |
| Dar permisos a **todo** un compartimento | Aceptable si el compartimento es de una sola aplicación |
| Reglas con `ANY` y sin compartimento | **No**: pueden incluir recursos ajenos |
| Llaves API dentro de la VM | **No** |
| Un grupo dinámico para todas las apps | **No**: uno por aplicación |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Grupo dinámico** | Conjunto de recursos definido por una regla |
| **Matching rule** | La regla (`ALL`/`ANY`) |
| **Instance principal** | La VM actúa como identidad |
| **Resource principal** | Una función/servicio actúa como identidad |
| **Metadatos** | Servicio local de la VM que entrega credenciales |
| **Etiqueta** | Marca (`app.nombre=tienda`) útil para reglas |

## 5. Cómo se usa
1. Define la regla acotada por compartimento: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Escribe la política mínima para el grupo ([unidad](../politicas-compartimentos/README.md)).
3. En Java, usa el proveedor de autenticación que corresponda ([uso en Java](uso-en-java.md)).
4. Revisa reglas peligrosas con el validador y la CLI: [`ejemplos/cli/grupos.sh`](ejemplos/cli/grupos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administrador de IAM | Crea y cambia grupos dinámicos y políticas | — |
| La VM / función | — | Solo lo que la política permite |
| Quien puede etiquetar | Puede **mover** recursos dentro de un grupo si la regla usa etiquetas | — |

- **Quien controla las etiquetas controla la pertenencia:** restringe quién puede etiquetar.
- **Acota siempre por compartimento.**
- **Un grupo dinámico por aplicación y entorno.**

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| `ALL` con compartimento + etiqueta | `ANY` abierto |
| Políticas mínimas por grupo | `manage all-resources` al grupo |
| Un grupo por aplicación | Un grupo para toda la empresa |
| Permitir etiquetar solo a quien corresponde | Etiquetas libres si definen permisos |
| Proveedor de credenciales del SDK | Llaves API en la VM |

## 8. Límites, costos y versiones
- **Costo:** gratuito.
- **Límites** (verifica): reglas por grupo, grupos dinámicos por tenancy.
- **Terraform:** `oci_identity_dynamic_group`.
- Con identity domains, los grupos dinámicos viven en un dominio; cita la política con `'Dominio'/'grupo'` si no es `Default`.
- Los cambios pueden tardar unos segundos en propagarse.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
