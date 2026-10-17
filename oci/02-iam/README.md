# Oracle OCI · 02 IAM

En OCI **todo está prohibido hasta que una política lo permite**. Este capítulo reúne las cuatro piezas de identidad: cada una responde una pregunta distinta.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Compartimentos, grupos y políticas](politicas-compartimentos/README.md) | ¿**Qué puede hacer** cada grupo y dónde? | Departamentos y libro de autorizaciones | Todo permiso de personas y aplicaciones |
| [Identity Domains](identity-domains/README.md) | ¿**Quién eres**? (usuarios, SSO, MFA) | La recepción del edificio | Personas, federación con tu IdP |
| [Grupos dinámicos y principales](dynamic-groups-principals/README.md) | ¿Cómo se identifica **una máquina o función**? | El uniforme de la empresa | Aplicaciones en VM y OCI Functions |
| [Workload Identity en OKE](workload-identity-oke/README.md) | ¿Cómo se identifica **un pod**? | Gafete de visitante con nombre y piso | Aplicaciones en Kubernetes |

## Árbol de decisión: «quiero…»

```
¿Quiero dar acceso a una PERSONA?
   └─ Identity Domain (SSO + MFA) → grupo → política en el compartimento

¿Quiero que una APLICACIÓN en VM llame a un servicio de OCI?
   └─ Grupo dinámico + política mínima + instance principal en el SDK

¿Es una función de OCI Functions?
   └─ Grupo dinámico (resource.type = 'fnfunc') + resource principal

¿Es un POD de OKE?
   └─ Workload identity: política con tipo + clúster + namespace + ServiceAccount

¿Quiero separar entornos?
   └─ Compartimentos tienda-prod / tienda-dev con políticas distintas

¿Quiero saber qué puede hacer alguien?
   └─ Revisa grupos del usuario → frases que citan esos grupos
```

## Comparativa

| Característica | Usuario/grupo | Grupo dinámico (VM/función) | Workload identity (pod) |
|---|---|---|---|
| **Quién es** | Persona | Recurso que coincide con una regla | ServiceAccount de un clúster |
| **Credencial** | Contraseña/SSO + MFA | Token de corta vida del servicio de metadatos | Token de corta vida intercambiado |
| **Granularidad** | Por grupo | Por regla (compartimento, etiqueta) | Por app (namespace + cuenta) |
| **Riesgo típico** | Sin MFA, cuentas huérfanas | `ANY` abierto, etiquetas libres | Cuenta `default`, falta `cluster_id` |
| **Proveedor Java** | Archivo/sesión | `InstancePrincipals…` / `ResourcePrincipal…` | `OkeWorkloadIdentity…` |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Equipo de desarrollo | Grupo `Desarrollo` en el dominio con SSO + MFA | Personas con rol |
| Dev y prod separados | Compartimentos `tienda-dev` / `tienda-prod` | Políticas distintas |
| API en VM que lee `comprobantes` | Grupo dinámico `ALL` + política `read objects` del bucket | Mínimo privilegio |
| Pedidos en OKE | Workload identity por ServiceAccount | Una identidad por servicio |
| Auditoría | Grupo `Auditores` con `inspect`/`read` | Revisión sin poder de cambio |

## Orden recomendado de adopción
1. Compartimentos por entorno y por plataforma/aplicación.
2. Dominio con SSO y MFA; grupos por rol.
3. Políticas pequeñas por equipo y compartimento (como código).
4. Grupos dinámicos acotados para VM y funciones.
5. Workload identity para pods.
6. Revisión periódica con los auditores de Java.

## Reglas transversales
- Mínimo privilegio: `read`/`use` antes que `manage`.
- Nada de `any-user` sin condición.
- Acota siempre por compartimento.
- Quien controla las etiquetas controla la pertenencia a grupos dinámicos.
- MFA para todos los humanos; sin llaves de larga vida en servidores.
- Todo como código y con revisión.

## Java en IAM: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Políticas | Linter de frases y auditor con `ListPolicies` | Núcleo puro + paginador del SDK |
| Identity Domains | Auditor de usuarios con SCIM (`IdentityDomainsClient`) | Paginación por `startIndex` |
| Grupos dinámicos | Analizador/validador de reglas + auditor | Núcleo puro + paginador |
| Workload identity | Selector de autenticación, generador de política, prueba de identidad | Validar antes de interpolar |

## Cómo se relaciona con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): tenancy, regiones y compartimentos.
- [Red](../01-red/README.md): las llamadas del SDK necesitan salida (NAT) o puerta de servicios.
- [Secretos](../03-secretos/README.md): quién puede leer qué secreto.
- [Compute](../04-compute/README.md): VM, funciones y OKE son los principales.
- [Gobierno](../09-gobierno/README.md): auditoría de cambios de políticas.
- [Terraform en OCI](../10-terraform/README.md): políticas y grupos como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
