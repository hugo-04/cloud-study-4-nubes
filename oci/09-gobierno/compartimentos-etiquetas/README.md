# Oracle OCI · Gobierno · Compartimentos, etiquetas y cuotas

Tres herramientas para que un tenancy con muchos equipos no se vuelva inmanejable: **compartimentos** (dónde vive cada recurso y quién puede tocarlo), **etiquetas** (a quién pertenece, cuánto cuesta, qué datos guarda) y **cuotas** (cuánto puede crear cada compartimento).

## 1. Qué es

**Analogía:** un edificio de oficinas. Los pisos y oficinas son compartimentos (cada equipo tiene su llave); las etiquetas en cada mueble dicen de qué área es y cuánto costó; y la administración pone topes: «este piso puede tener como máximo 20 escritorios» (cuotas).

```
 Tenancy (raíz)
  ├─ red-compartida            (VCN, DRG)        etiquetas: Gobierno.centro_costo=plataforma
  ├─ seguridad                 (Vault, Cloud Guard)
  └─ modalima
       ├─ prod   ← cuota: máx. 40 OCPU, sin GPU    etiquetas obligatorias por defecto
       │   ├─ tienda   ├─ datos
       └─ no-prod ← cuota: máx. 16 OCPU, apagado nocturno
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Compartimento** | Contenedor lógico jerárquico (hasta 6 niveles bajo la raíz *(verifica)*); las políticas se heredan hacia abajo |
| **Etiqueta libre (freeform)** | Clave/valor sin control; útil para pruebas, no para gobierno |
| **Espacio de etiquetas (namespace)** | Agrupa etiquetas definidas; se puede retirar pero no borrar fácilmente |
| **Etiqueta definida** | Clave con validación (lista de valores) y permisos de uso |
| **Etiqueta por defecto (tag default)** | Se aplica automáticamente a todo recurso creado en un compartimento; puede ser **obligatoria** |
| **Variables** | `${iam.principal.name}`, `${oci.datetime}` en etiquetas por defecto |
| **Cuotas** | Sentencias `set`, `unset`, `zero` sobre familias de recursos por compartimento |
| **Límites de servicio** | Topes de Oracle por tenancy/región; las cuotas trabajan **debajo** de ellos |

### Lo que hereda y lo que no
- Las **políticas** se heredan hacia los hijos.
- Las **etiquetas por defecto** se aplican a recursos creados en el compartimento y sus hijos.
- Mover un recurso de compartimento cambia sus políticas efectivas (y puede romper accesos).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Separar producción de no producción | Compartimentos distintos |
| Saber cuánto gasta cada producto | Etiqueta definida `centro_costo` obligatoria |
| Evitar que no-prod cree GPU | Cuota `zero` |
| Separar por tipo de recurso («todas las VM aquí») | **No**: separa por dueño/ciclo de vida |
| Una jerarquía de 6 niveles «por si acaso» | **No**: 2–3 niveles bastan casi siempre |
| Usar etiquetas libres para facturación | **No**: no se validan |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Landing zone** | Estructura base de compartimentos, red y seguridad |
| **Etiqueta obligatoria** | Sin ella no se crea el recurso |
| **Etiqueta de costo** | Etiqueta activada para filtrar en el análisis de costos |
| **Cuota** | Tope propio por compartimento |
| **Límite de servicio** | Tope de Oracle por tenancy |

## 5. Cómo se usa
1. Estructura, espacio de etiquetas, etiquetas con validación, etiqueta por defecto obligatoria y cuotas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Audita compartimentos sin etiquetas o con valores inválidos: [uso en Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/gobierno.sh`](ejemplos/cli/gobierno.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores de tenancy | `manage compartments`, `manage tag-namespaces`, `manage quota` | — |
| Equipos | `use tag-namespaces` para aplicar etiquetas | — |
| Auditoría | `inspect compartments`, `read tag-namespaces` | — |

- Nadie debería trabajar en el compartimento raíz.
- Restringe quién puede **mover** recursos entre compartimentos.
- Las etiquetas no son secretos: no pongas datos sensibles en ellas.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Compartimentos por dueño y entorno | Por tipo de recurso |
| 3–5 etiquetas definidas obligatorias | 30 etiquetas que nadie llena bien |
| Valores validados (lista) | Texto libre en `centro_costo` |
| Cuotas en no-prod desde el día uno | Descubrir el gasto a fin de mes |
| Todo como código | Crear compartimentos a mano |

## 8. Límites, costos y versiones
- **Costo:** compartimentos, etiquetas y cuotas no tienen costo.
- **Límites** (verifica): profundidad de compartimentos, espacios de etiquetas, etiquetas por recurso, sentencias de cuota.
- **Terraform:** `oci_identity_compartment`, `oci_identity_tag_namespace`, `oci_identity_tag`, `oci_identity_tag_default`, `oci_limits_quota`.
- **SDK:** `IdentityClient`, `QuotasClient` (`oci-java-sdk-identity`, `oci-java-sdk-limits`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
