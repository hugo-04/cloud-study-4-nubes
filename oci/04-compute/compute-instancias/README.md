# Oracle OCI · Compute · Instancias (máquinas virtuales)

La máquina virtual clásica: tú eliges cuánta CPU y memoria, el sistema operativo y cómo se conecta. Es la base sobre la que OKE, balanceadores y bases de datos se apoyan, y la opción cuando necesitas control total.

## 1. Qué es

**Analogía:** alquilar un local comercial vacío. Eliges el tamaño (forma), la ubicación (dominio de disponibilidad) y qué instalar; el edificio (Oracle) pone luz, agua y seguridad física. Pagas mientras el local esté abierto.

```
 Imagen (SO) + Forma (CPU/RAM) + Volumen de arranque + VNIC (subred, NSG)
                      │
                  Instancia ── metadatos (169.254.169.254) ── identidad (instance principal)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Forma** (*shape*) | Tipo de máquina: `VM.Standard.E5.Flex` (AMD), `VM.Standard.A1.Flex` (Arm/Ampere), `VM.Standard3.Flex` (Intel) *(verifica la oferta de tu región)* |
| **Forma flexible** | Tú eliges OCPU y memoria dentro de rangos |
| **Imagen** | Plantilla del sistema operativo (Oracle Linux, Ubuntu, imagen propia) |
| **Volumen de arranque** | Disco del sistema; sobrevive si conservas la instancia detenida |
| **Volumen de bloques** | Discos adicionales |
| **VNIC** | Tarjeta de red: subred, NSG, IP privada (y pública si la pides) |
| **Dominio de disponibilidad / de fallos** | Separación física dentro de una región |
| **cloud-init** | Script de arranque (`user_data`) |
| **Servicio de metadatos** | `http://169.254.169.254/opc/v2/`; entrega datos e identidad |

### Estados
`PROVISIONING` → `RUNNING` ⇄ `STOPPING`/`STOPPED` → `TERMINATING` → `TERMINATED`. Una instancia **detenida** no cobra cómputo, pero sí discos.

### Escalar
- **Vertical:** cambiar OCPU/memoria en formas flexibles (reinicia).
- **Horizontal:** *instance pool* + *autoscaling* detrás de un balanceador.
- **Interrumpibles** (*preemptible*): más baratas, para trabajo tolerante a cortes.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Software con requisitos de SO o agentes propios | VM |
| Aplicación contenerizada | [OKE](../oke/README.md) o [Container Instances](../container-instances/README.md) |
| Evento corto y esporádico | [Functions](../functions/README.md) |
| Dev/pruebas que se usan en horario de oficina | VM con apagado programado |
| Servidor de base de datos «hecho a mano» | **No**: servicios administrados |
| Acceso SSH desde Internet a todo | **No**: Bastion / VPN |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **OCPU** | Núcleo físico (2 vCPU con hyper-threading en x86) |
| **Forma flexible** | Eliges tú CPU y memoria |
| **Instance principal** | La VM se autentica sin llaves |
| **IMDSv2** | Versión segura del servicio de metadatos |
| **Fault domain** | Rack distinto dentro del mismo dominio |
| **Preemptible** | Instancia que Oracle puede recuperar |

## 5. Cómo se usa
1. Crea la VM en subred privada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Acceso por Bastion o VPN, no por IP pública.
3. Etiqueta con `horario` para apagar fuera de oficina ([Java](uso-en-java.md)).
4. CLI: [`ejemplos/cli/instancias.sh`](ejemplos/cli/instancias.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de operaciones | `manage instance-family` en su compartimento | SSH por Bastion con llaves de corta vida |
| La VM | — | Instance principal con política mínima |
| Aplicación | — | Reglas de NSG y de la propia VM |

- **IMDSv2 obligatorio** y metadatos legados deshabilitados.
- **Sin IP pública**; NSG por rol.
- Parches y agentes (Oracle Cloud Agent) al día.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Formas flexibles con tamaño justo | Sobredimensionar «por si acaso» |
| Subred privada + Bastion | IP pública y SSH abierto |
| Imágenes endurecidas y cloud-init | Configurar a mano cada VM |
| Instance principal | Llaves API en el disco |
| Apagar dev fuera de horario | Dejar todo encendido 24/7 |
| Etiquetas de responsable y entorno | VM huérfanas |

## 8. Límites, costos y versiones
- **Costo:** por OCPU-hora y GB-hora de memoria; discos aparte; las formas Arm A1 incluyen cuota de nivel siempre gratuito *(verifica)*.
- **Límites** (verifica): OCPU por forma y región, volúmenes por instancia.
- **Terraform:** `oci_core_instance`, `oci_core_instance_pool`, `oci_autoscaling_auto_scaling_configuration`.
- **SDK:** `ComputeClient` (`oci-java-sdk-core`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
