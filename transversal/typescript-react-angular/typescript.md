# Transversal · TypeScript para frontends de microservicios

TypeScript es JavaScript con **tipos estáticos** que desaparecen al compilar. En un frontend que habla con microservicios, los tipos son el **contrato** con el backend: si el servicio cambia la respuesta, el compilador lo dice antes que el usuario.

## 1. Tipos que más se usan
| Herramienta | Para qué | Ejemplo |
|---|---|---|
| `type` / `interface` | Formas de objetos | `type Pedido = { id: string; total: number }` |
| Uniones literales | Valores cerrados | `type Estado = 'CREADO' \| 'PAGADO'` |
| **Uniones discriminadas** | Modelar estados sin `null` sorpresa | `{ tipo: 'ok'; datos } \| { tipo: 'error'; problema }` |
| Genéricos | Reutilizar con tipos | `Pagina<T>` |
| *Utility types* | Derivar tipos | `Partial<T>`, `Pick<T,K>`, `Omit<T,K>`, `Readonly<T>`, `Record<K,V>` |
| *Narrowing* | Afinar el tipo con comprobaciones | `if ('error' in r)`, `switch (r.tipo)` |
| `unknown` | Datos externos sin confiar | Validar antes de usar |
| `satisfies` | Comprobar sin perder el tipo literal | `const rutas = {...} satisfies Record<string, string>` |
| `strict: true` | Activa todo lo anterior en serio | Siempre |

## 2. Contrato con el backend: tipos, validación y errores
```ts
// Tipos del contrato (idealmente generados desde OpenAPI del servicio)
export type EstadoPedido = 'CREADO' | 'PAGADO' | 'ENVIADO' | 'ENTREGADO' | 'CANCELADO';

export interface Pedido {
  readonly id: string;
  cliente: string;
  totalCentimos: number;
  estado: EstadoPedido;
}

export interface Pagina<T> {
  elementos: T[];
  siguiente: string | null;
}

/** Errores HTTP en formato ProblemDetail (RFC 9457), como los devuelve el backend. */
export interface Problema {
  type?: string;
  title: string;
  status: number;
  detail?: string;
}

/** Resultado discriminado: el compilador obliga a tratar los dos casos. */
export type Resultado<T> = { ok: true; datos: T } | { ok: false; problema: Problema };

const ESTADOS: readonly EstadoPedido[] = ['CREADO', 'PAGADO', 'ENVIADO', 'ENTREGADO', 'CANCELADO'];

/** Validación en el borde: lo que llega por la red es `unknown` hasta demostrar lo contrario. */
export function esPedido(x: unknown): x is Pedido {
  if (typeof x !== 'object' || x === null) return false;
  const o = x as Record<string, unknown>;
  return typeof o.id === 'string' && typeof o.cliente === 'string'
    && typeof o.totalCentimos === 'number' && ESTADOS.includes(o.estado as EstadoPedido);
}

/** fetch con timeout, cancelación, idempotency key y errores tipados. */
export async function pedirJson<T>(
  url: string,
  validar: (x: unknown) => x is T,
  opciones: { metodo?: 'GET' | 'POST'; cuerpo?: unknown; idempotencia?: string; timeoutMs?: number; senal?: AbortSignal } = {},
): Promise<Resultado<T>> {
  const control = new AbortController();
  const reloj = setTimeout(() => control.abort(), opciones.timeoutMs ?? 5000);
  opciones.senal?.addEventListener('abort', () => control.abort());
  try {
    const r = await fetch(url, {
      method: opciones.metodo ?? 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...(opciones.idempotencia ? { 'Idempotency-Key': opciones.idempotencia } : {}),
      },
      body: opciones.cuerpo === undefined ? undefined : JSON.stringify(opciones.cuerpo),
      signal: control.signal,
      credentials: 'include',
    });
    const json: unknown = await r.json().catch(() => null);
    if (!r.ok) {
      const p = (json ?? {}) as Partial<Problema>;
      return { ok: false, problema: { title: p.title ?? r.statusText, status: r.status, detail: p.detail } };
    }
    return validar(json) ? { ok: true, datos: json } : { ok: false, problema: { title: 'Respuesta inválida', status: 502 } };
  } catch (e) {
    const abortado = e instanceof DOMException && e.name === 'AbortError';
    return { ok: false, problema: { title: abortado ? 'Tiempo agotado' : 'Sin conexión', status: 0 } };
  } finally {
    clearTimeout(reloj);
  }
}

export function formatearSoles(centimos: number): string {
  return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(centimos / 100);
}
```

## 3. Tipos derivados y exhaustividad
```ts
type Pedido = { id: string; cliente: string; totalCentimos: number; estado: 'CREADO' | 'PAGADO' | 'CANCELADO' };

// Lo que el formulario envía: sin id ni estado (los decide el servidor)
type CrearPedido = Omit<Pedido, 'id' | 'estado'>;

// Edición parcial
type CambiosPedido = Partial<Pick<Pedido, 'cliente'>>;

const etiquetas = {
  CREADO: 'Creado',
  PAGADO: 'Pagado',
  CANCELADO: 'Cancelado',
} satisfies Record<Pedido['estado'], string>;   // si se agrega un estado, esto no compila hasta cubrirlo

function color(estado: Pedido['estado']): string {
  switch (estado) {
    case 'CREADO': return 'gris';
    case 'PAGADO': return 'verde';
    case 'CANCELADO': return 'rojo';
    default: {
      const imposible: never = estado;   // exhaustividad comprobada por el compilador
      return imposible;
    }
  }
}

export const ejemplo: { crear: CrearPedido; cambios: CambiosPedido; etiqueta: string; color: string } = {
  crear: { cliente: 'ana', totalCentimos: 12990 },
  cambios: {},
  etiqueta: etiquetas.PAGADO,
  color: color('PAGADO'),
};
```

## 4. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| `strict: true` | `any` para «avanzar rápido» |
| Generar tipos desde el OpenAPI del servicio | Copiar a mano los DTO |
| Validar datos externos (`unknown` + guardas o una librería de esquemas) | Confiar en que la API siempre responde bien |
| Uniones discriminadas para estados de carga/error | Banderas `loading`, `error`, `data` sueltas que se contradicen |
| Montos en céntimos (enteros) | Sumar precios con decimales binarios |
