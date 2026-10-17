# Transversal · Arquitectura · Estilos, capas y paquetes

## 1. Monolito, monolito modular o microservicios

| Criterio | Monolito | Monolito modular | Microservicios |
|---|---|---|---|
| Despliegue | Uno | Uno | Uno por servicio |
| Límites internos | Difusos | Módulos con API interna y reglas | Red + contratos |
| Datos | Una base | Una base, esquemas por módulo | Base por servicio |
| Equipos | 1–2 | Varios, mismo repositorio | Muchos, autónomos |
| Costo operativo | Bajo | Bajo | Alto (observabilidad, red, despliegues) |
| Consistencia | ACID | ACID | Eventual (sagas) |
| Escalado | Todo junto | Todo junto | Por servicio |

### Cuándo sí y cuándo no
| Si… | Entonces |
|---|---|
| El dominio aún cambia mucho y hay un solo equipo | **Monolito modular**: límites claros sin costo de red |
| Partes con ritmos de cambio, carga o equipos muy distintos | Extraer esas partes como servicios |
| Necesitas transacciones fuertes entre casi todo | Probablemente es un solo servicio |
| No hay CI/CD, observabilidad ni automatización | Microservicios aún no |
| «Netflix lo hace» | No es un argumento |

**Regla práctica:** empieza por un monolito modular bien cortado (por subdominio); si un módulo necesita escalar o desplegarse aparte, ya tiene la frontera lista para salir (strangler fig).

## 2. Capas clásicas
```
 Controlador (HTTP, validación de entrada, mapeo DTO)
   ▼
 Servicio / caso de uso (reglas de aplicación, transacción)
   ▼
 Dominio (entidades, value objects, reglas de negocio)
   ▼
 Repositorio / clientes (persistencia, APIs externas)
```
Simple y suficiente para CRUD. Su debilidad: el dominio suele terminar dependiendo de la persistencia (anotaciones JPA, excepciones de la base).

## 3. Arquitectura hexagonal (puertos y adaptadores)
El **dominio y los casos de uso** están en el centro y **definen interfaces (puertos)**; la infraestructura (web, base, broker, SDK) son **adaptadores** que las implementan. Las dependencias apuntan **hacia adentro**.

```
            adaptador web (REST)      adaptador de mensajería (consumidor)
                    │ puerto de entrada (caso de uso)
                    ▼
            ┌──────────────────────────────┐
            │  aplicación: CrearPedido      │
            │  dominio: Pedido, Dinero      │
            └──────────────────────────────┘
                    │ puertos de salida (interfaces del dominio)
                    ▼
     adaptador JPA (RepositorioPedidos)   adaptador HTTP (Pasarela)   adaptador broker (Publicador)
```

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/* ===== dominio: sin frameworks ===== */
record Dinero(long centimos) {
    Dinero {
        if (centimos < 0) {
            throw new IllegalArgumentException("monto negativo");
        }
    }

    Dinero mas(Dinero o) {
        return new Dinero(centimos + o.centimos);
    }

    Dinero por(int n) {
        return new Dinero(centimos * n);
    }
}

record Linea(String sku, int cantidad, Dinero precio) {
    Dinero subtotal() {
        return precio.por(cantidad);
    }
}

/** Agregado: protege sus invariantes; se modifica solo por sus métodos. */
final class PedidoDominio {
    private final String id;
    private final String cliente;
    private final List<Linea> lineas = new ArrayList<>();
    private boolean confirmado;

    PedidoDominio(String id, String cliente) {
        this.id = id;
        this.cliente = cliente;
    }

    void agregar(Linea l) {
        if (confirmado) {
            throw new IllegalStateException("pedido confirmado: no admite cambios");
        }
        if (lineas.size() >= 100) {
            throw new IllegalStateException("máximo 100 líneas");
        }
        lineas.add(l);
    }

    Dinero total() {
        return lineas.stream().map(Linea::subtotal).reduce(new Dinero(0), Dinero::mas);
    }

    void confirmar() {
        if (lineas.isEmpty()) {
            throw new IllegalStateException("pedido vacío");
        }
        confirmado = true;
    }

    String id() {
        return id;
    }

    String cliente() {
        return cliente;
    }

    boolean confirmado() {
        return confirmado;
    }
}

/* ===== puertos de salida (los define el dominio/aplicación) ===== */
interface RepositorioPedidosPuerto {
    void guardar(PedidoDominio p);

    Optional<PedidoDominio> buscar(String id);
}

interface PasarelaPuerto {
    boolean autorizar(String idPedido, Dinero monto);
}

/* ===== caso de uso (puerto de entrada) ===== */
record ComandoCrearPedido(String cliente, List<Linea> lineas) { }

final class CrearPedido {
    private final RepositorioPedidosPuerto repo;
    private final PasarelaPuerto pasarela;

    CrearPedido(RepositorioPedidosPuerto repo, PasarelaPuerto pasarela) {
        this.repo = repo;
        this.pasarela = pasarela;
    }

    String ejecutar(ComandoCrearPedido c) {
        var p = new PedidoDominio(UUID.randomUUID().toString(), c.cliente());
        c.lineas().forEach(p::agregar);
        if (!pasarela.autorizar(p.id(), p.total())) {
            throw new IllegalStateException("pago rechazado");
        }
        p.confirmar();
        repo.guardar(p);
        return p.id();
    }
}

/* ===== adaptador de salida en memoria (para pruebas o demo) ===== */
final class RepositorioEnMemoria implements RepositorioPedidosPuerto {
    private final java.util.Map<String, PedidoDominio> datos = new java.util.concurrent.ConcurrentHashMap<>();

    public void guardar(PedidoDominio p) {
        datos.put(p.id(), p);
    }

    public Optional<PedidoDominio> buscar(String id) {
        return Optional.ofNullable(datos.get(id));
    }
}
```

Adaptador de entrada (web) en Spring, que solo traduce:
```java
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
class PedidoWebAdaptador {
    record LineaDto(String sku, int cantidad, long precioCentimos) { }

    record CrearDto(String cliente, List<LineaDto> lineas) { }

    private final CrearPedido casoDeUso;

    PedidoWebAdaptador(CrearPedido casoDeUso) {
        this.casoDeUso = casoDeUso;
    }

    @PostMapping("/v1/pedidos")
    String crear(@RequestBody CrearDto dto) {
        var lineas = dto.lineas().stream().map(l -> new Linea(l.sku(), l.cantidad(), new Dinero(l.precioCentimos()))).toList();
        return casoDeUso.ejecutar(new ComandoCrearPedido(dto.cliente(), lineas));
    }
}
```

## 4. Clean architecture
Misma idea con anillos con nombre: **entidades** → **casos de uso** → **adaptadores de interfaz** → **frameworks y drivers**. La **regla de dependencia**: el código de un anillo solo conoce a los interiores. Hexagonal y clean se diferencian sobre todo en vocabulario; elige uno y sé consistente.

| Concepto | Hexagonal | Clean |
|---|---|---|
| Centro | Dominio + aplicación | Entidades + casos de uso |
| Interfaces hacia afuera | Puertos | *Gateways* / interfaces de casos de uso |
| Implementaciones | Adaptadores | Adaptadores de interfaz |
| Regla | Dependencias hacia adentro | Regla de dependencia |

## 5. DDD táctico en una tabla
| Pieza | Qué es | En el ejemplo |
|---|---|---|
| Value object | Inmutable, igualdad por valor, se valida al crear | `Dinero`, `Linea` |
| Entidad | Identidad propia que perdura | `PedidoDominio` |
| Agregado | Límite de consistencia; se cambia por su raíz | `PedidoDominio` con sus líneas |
| Evento de dominio | Algo que pasó y a otros les importa | `PedidoConfirmado` (a publicar con outbox) |
| Repositorio | Colección de agregados (puerto) | `RepositorioPedidosPuerto` |
| Bounded context | Frontera donde un modelo tiene significado | «Ventas» vs «Despacho» |

## 6. Organización de paquetes
| Estilo | Estructura | Valoración |
|---|---|---|
| Por capa | `controller/`, `service/`, `repository/` | Fácil al inicio; mezcla funcionalidades y todo es público |
| **Por funcionalidad** (recomendado) | `pedidos/`, `pagos/`, `catalogo/` cada uno con sus capas internas | Cohesión, visibilidad de paquete, módulos listos para extraer |
| Hexagonal por funcionalidad | `pedidos/dominio`, `pedidos/aplicacion`, `pedidos/adaptadores/{web,persistencia}` | Explícito; ideal para dominios ricos |

```
com.modalima.tienda
 ├─ pedidos
 │   ├─ dominio        (PedidoDominio, Dinero, eventos, puertos)
 │   ├─ aplicacion     (CrearPedido, ConsultarPedido)
 │   └─ adaptadores
 │       ├─ web        (controladores, DTOs)
 │       ├─ persistencia (entidades JPA, repositorios)
 │       └─ mensajeria (publicador, consumidores)
 ├─ pagos ...
 └─ compartido         (solo lo verdaderamente común; vigílalo)
```

Reglas que conviene **verificar automáticamente** (con ArchUnit, ver [testing](testing.md)):
- `dominio` no depende de `adaptadores` ni de frameworks.
- Un módulo no accede a los internos de otro (solo a su API).
- Sin ciclos entre paquetes.
