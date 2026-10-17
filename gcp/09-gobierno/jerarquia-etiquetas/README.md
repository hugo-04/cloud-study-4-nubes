# Google Cloud · Gobierno · Jerarquía de recursos, etiquetas y tags

La **jerarquía** (organización → carpetas → proyectos → recursos) es el esqueleto del gobierno: IAM, políticas de organización y presupuestos se **heredan** hacia abajo. Sobre ella hay dos formas de etiquetar: **labels** (pares clave-valor libres para costos y búsqueda) y **tags** (recursos de primera clase, con permisos propios, que se usan en **condiciones de IAM, políticas de organización y firewall**).

## 1. Qué es

**Analogía:** el organigrama de una empresa (jerarquía) + el color de la credencial (tag, que abre puertas) + la etiqueta de centro de costo en la factura (label, que solo informa).

```
 Organización modalima.example
   ├── carpeta "plataforma"  (tag entorno=compartido)
   │     └── proyecto modalima-red-hub
   ├── carpeta "produccion"  (tag entorno=prod  → hereda a todo lo de abajo)
   │     ├── proyecto modalima-tienda-prod   labels: equipo=tienda, centro-costo=cc-101
   │     └── proyecto modalima-datos-prod
   └── carpeta "no-produccion" (tag entorno=no-prod)
         └── proyecto modalima-tienda-dev
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Organización** | Raíz ligada al dominio de Cloud Identity / Workspace |
| **Carpetas** | Agrupación por entorno, área o unidad de negocio (hasta 10 niveles) |
| **Proyectos** | Límite de facturación, APIs y cuotas; ID inmutable |
| **Herencia** | IAM y políticas bajan; un permiso dado arriba no se quita abajo (salvo políticas de denegación) |
| **Labels** | Clave-valor en recursos; llegan a la exportación de facturación |
| **Tags** | `TagKey` (p. ej. `entorno`) + `TagValue` (`prod`) + `TagBinding` al recurso; se heredan |
| **Condiciones** | `resource.matchTag('123/entorno', 'prod')` en IAM y políticas de organización |
| **Gravámenes (liens)** | Protegen proyectos contra borrado |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Separar prod de no-prod con políticas distintas | Carpetas + tag `entorno` |
| Repartir costos por equipo | Labels `equipo`, `centro-costo` |
| Dar acceso solo a recursos de un entorno | Condición de IAM con tags |
| Firewall por entorno | Tags seguros en reglas de firewall de red |
| Datos sensibles de clasificación | Tag (controlado), no label (cualquiera lo cambia) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Herencia** | Lo de arriba aplica a todo lo de abajo |
| **Label** | Etiqueta informativa sin permisos propios |
| **Tag** | Etiqueta con permisos y efecto en políticas |
| **Tag efectivo** | El tag que aplica, propio o heredado |
| **Lien** | Candado contra borrado del proyecto |

## 5. Cómo se usa
1. Carpetas, tag `entorno`, vínculo y labels obligatorios: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Auditoría de labels y tags de los proyectos de una carpeta en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/jerarquia.sh`](ejemplos/cli/jerarquia.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/resourcemanager.folderAdmin`, `roles/resourcemanager.tagAdmin` | — |
| Equipos | `roles/resourcemanager.tagUser` (vincular valores permitidos) | — |
| Auditoría | `roles/resourcemanager.folderViewer`, `roles/resourcemanager.tagViewer` | — |

- `roles/owner` y `roles/editor` nunca a nivel de organización ni carpeta.
- Tags para decisiones de seguridad; labels solo para costos y búsqueda.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Carpetas por entorno arriba | Proyectos sueltos bajo la organización |
| Tags en carpetas (heredan) | Tags proyecto por proyecto a mano |
| Labels obligatorios validados en CI | Labels con nombres libres (`Equipo`, `team`) |
| Liens en proyectos críticos | Proyectos de producción borrables con un clic |
| Jerarquía como código | Mover proyectos sin revisar herencia |

## 8. Límites, costos y versiones
- **Costo:** sin cargo.
- **Límites** (verifica): 10 niveles de carpetas, 64 labels por recurso, 50 tags por recurso, 1 000 valores por clave de tag.
- **Terraform:** `google_folder`, `google_tags_tag_key`, `google_tags_tag_value`, `google_tags_tag_binding`, `google_resource_manager_lien`.
- **Java:** `google-cloud-resourcemanager` (`ProjectsClient`, `TagBindingsClient`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
