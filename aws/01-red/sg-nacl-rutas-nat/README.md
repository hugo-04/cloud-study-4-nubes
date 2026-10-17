# AWS · Red · Grupos de seguridad, NACL, rutas y NAT

Quién puede hablar con quién y por dónde sale el tráfico. Cuatro piezas que se confunden mucho: **grupos de seguridad** (el portero de cada recurso), **NACL** (la reja de la subred), **tablas de rutas** (los letreros) y **NAT Gateway** (la salida para los privados).

## 1. Qué es

**Analogía:** un edificio de oficinas. El **grupo de seguridad** es el portero de *cada oficina*: recuerda a quién dejó entrar y deja salir a esa persona sin preguntar de nuevo. La **NACL** es el control de acceso del *piso completo*: no recuerda a nadie, revisa cada paso de ida y de vuelta con una lista numerada. La **tabla de rutas** son los letreros del pasillo. El **NAT** es el mensajero que sale a la calle por los de adentro.

```
 internet ─► IGW ─► [ruta pública] ─► ALB (SG-alb: 443 desde 0.0.0.0/0)
                                         │
                       NACL de la subred │   SG-app: 8080 solo desde SG-alb
                                         ▼
                                   contenedores ──► SG-datos: 5432 solo desde SG-app
                                         │                         ▼
                              [ruta 0.0.0.0/0 → NAT] ──► internet     Aurora
```

## 2. Cómo funciona por dentro

### Grupos de seguridad (SG) — a nivel de interfaz de red
- **Con estado:** si permites la entrada, la respuesta sale sola; si permites la salida, la respuesta vuelve sola.
- **Solo permisos (allow):** no existen reglas de denegación. Lo que no está permitido, está denegado.
- Por defecto: **entrada denegada**, **salida permitida a todo**.
- Todas las reglas se evalúan juntas (se suman); el orden no importa.
- El origen puede ser un **CIDR**, una **lista de prefijos** o **otro grupo de seguridad** (la forma recomendada: «la app puede hablar con la base», sin saber IP).
- Se asocian a la **ENI** (instancia, tarea de Fargate, endpoint, balanceador, base de datos…). Una ENI admite varios grupos (se suman).
- Los cambios aplican **al instante** y a las conexiones nuevas; las existentes siguen mientras se rastrean.

### NACL — a nivel de subred
- **Sin estado:** debes permitir la ida **y la vuelta** (puertos efímeros `1024–65535`).
- Tiene reglas de **permitir y denegar**, numeradas: se evalúan de menor a mayor y **gana la primera que coincide**. La última (`*`) deniega todo.
- La NACL predeterminada permite todo; una NACL **nueva** deniega todo hasta que añadas reglas.
- Una subred tiene **una** NACL; una NACL puede servir a muchas subredes.

### Tablas de rutas
- Cada subred está asociada a una tabla; si no, usa la principal de la VPC.
- Siempre existe la ruta **local** (tráfico dentro de la VPC), que no se puede quitar.
- Gana la **ruta más específica** (prefijo más largo); a igualdad, local > estática > propagada.
- Destinos: IGW, NAT, Transit Gateway, peering, endpoints de puerta de enlace, VPN, interfaces de red.
- Una **lista de prefijos** administrada (p. ej. la de S3) evita copiar rangos.

### NAT Gateway
- Zonal: vive en **una subred pública** y necesita una Elastic IP (NAT público).
- Solo permite conexiones **iniciadas desde dentro**.
- Cobra **por hora y por GB procesado**.
- Cierra conexiones inactivas a los **350 s** (responde RST al intentar usarlas).
- Límite práctico: unas 55 000 conexiones simultáneas por IP de NAT hacia un mismo destino (IP+puerto+protocolo). *Verifica los valores vigentes.* Existe también un NAT **privado** (sin internet, para redes superpuestas o locales) y un modo regional más reciente: verifica disponibilidad.

### Quién gana si chocan
Para llegar de A a B el tráfico debe pasar **todo**: la ruta correcta, la NACL de la subred (salida de A y entrada de B, con retorno), el SG del origen (salida) y el SG del destino (entrada). Uno que diga que no, basta.

## 3. Para qué sirve y cuándo NO

| Quiero… | Uso |
|---|---|
| Que solo el balanceador hable con la aplicación | SG de la app con origen = SG del balanceador |
| Que la base solo hable con la app | SG de datos con origen = SG de la app |
| Bloquear una IP maliciosa concreta | **NACL** (o AWS WAF en el borde) |
| Que los privados salgan a internet | Ruta `0.0.0.0/0 → NAT` |
| Que los privados lleguen a S3 sin pagar NAT | Endpoint de puerta de enlace (siguiente servicio) |
| Segmentar por entorno | Cuentas distintas + SG por rol, no una NACL por equipo |

**Cuándo NO:** no uses NACL como mecanismo principal (pocas reglas, sin estado, difíciles de mantener); no abras puertos a `0.0.0.0/0` excepto 443/80 del balanceador público.

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Con estado / sin estado** | SG recuerda la conexión; NACL no |
| **Puertos efímeros** | Los puertos altos que el cliente abre para recibir la respuesta |
| **Referencia entre SG** | «Permitir desde los miembros de ese grupo», sin IP |
| **Lista de prefijos** | Conjunto de CIDR con nombre, reutilizable |
| **Ruta más específica** | `/24` gana a `/16` aunque esté «debajo» |
| **ENI** | La tarjeta de red a la que se pega el SG |
| **NAT público / privado** | Con o sin salida a internet |
| **Reglas «todo»** | Protocolo `-1` = todos los puertos: casi nunca hace falta |

## 5. Cómo se usa
1. Un SG **por rol** (`alb`, `app`, `datos`, `endpoints`), con nombre y etiquetas.
2. Reglas de entrada **por referencia a SG**; CIDR solo para el exterior o la red local.
3. Salida: en producción, restringe a lo necesario (servicios propios, endpoints, 443) en vez de «todo».
4. NACL: déjala por defecto, salvo una capa extra en subredes de datos o un bloqueo puntual.
5. Rutas: una tabla por nivel y por AZ para los NAT. Todo en Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
6. Audita con [`ejemplos/cli/auditar-sg.sh`](ejemplos/cli/auditar-sg.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | `ec2:*SecurityGroup*`, `ec2:*NetworkAcl*`, `ec2:*Route*` acotado por etiqueta/VPC | — |
| Desarrolladores | Solo `Describe*` | — |
| Auditoría | `ec2:Describe*` + AWS Config | — |
| Quien abre un puerto «temporal» | **Nadie en producción a mano**: cambio con revisión | — |

- AWS Config tiene reglas administradas (p. ej. «SSH no restringido», «SG sin uso») y Security Hub las agrupa.
- **No abras 22/3389**: usa Session Manager (SSM) y la IAM para entrar a las máquinas.
- Etiqueta cada regla con el motivo (`description`).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Referenciar SG entre capas | Copiar CIDR de subredes en cada regla |
| Un SG por rol y descripción en cada regla | Un SG «todo-abierto» compartido por todos |
| Restringir la salida en producción | Dejar `0.0.0.0/0` en todo el tráfico de salida sin mirar |
| Un NAT por AZ, con su tabla de rutas | Un NAT para tres zonas |
| NACL por defecto y simples | Cientos de reglas NACL que nadie entiende |
| Listas de prefijos para rangos repetidos | Pegar 40 CIDR en 12 grupos |
| Revisar SG sin uso y reglas anchas | Acumular reglas «temporales» |

## 8. Límites, costos y versiones
- **Costo:** SG, NACL y rutas son gratis. **NAT Gateway:** por hora + por GB (el rubro típico más doloroso). *Verifica precios.*
- **Límites típicos** (ajustables; verifica): reglas por SG (≈60 de entrada y 60 de salida), SG por ENI (5 por defecto), reglas por NACL (20 por sentido por defecto), rutas por tabla.
- **Terraform:** proveedor `aws` 6.x, con recursos `aws_vpc_security_group_*_rule` (una regla por recurso). Ejemplos validados con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
