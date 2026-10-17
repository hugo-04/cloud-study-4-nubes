# Transversal · React para frontends de microservicios

React construye interfaces con **componentes funcionales** y **hooks**: el componente es una función del estado; cuando el estado cambia, React vuelve a dibujar lo necesario. Versión objetivo: **React 19** con TypeScript *(verifica)*.

## 1. Piezas
| Pieza | Para qué | Regla |
|---|---|---|
| `useState` | Estado local simple | Inmutable: crea objetos nuevos |
| `useReducer` | Estado con muchas transiciones (carrito) | Acciones como unión discriminada |
| `useEffect` | Sincronizar con algo externo (red, suscripciones) | Limpia en el retorno (abortar fetch) |
| `useMemo` / `useCallback` | Evitar cálculos o recreaciones caras | Solo si mides un problema |
| Hooks propios | Reutilizar lógica (`usePedido`) | Empiezan con `use` |
| Contexto | Datos globales poco cambiantes (sesión, tema) | No como «base de datos» global |
| Librería de datos del servidor (TanStack Query u otra) | Caché, reintentos, invalidación | Preferible a reimplementarlo |

## 2. Carrito con `useReducer` (estado de negocio tipado)
```tsx
import { useReducer } from 'react';

type Linea = { sku: string; nombre: string; precioCentimos: number; cantidad: number };
type Carrito = { lineas: Linea[]; cupon: string | null };
type Accion =
  | { tipo: 'agregar'; linea: Omit<Linea, 'cantidad'> }
  | { tipo: 'quitar'; sku: string }
  | { tipo: 'cupon'; codigo: string | null };

export function reducir(c: Carrito, a: Accion): Carrito {
  switch (a.tipo) {
    case 'agregar': {
      const existe = c.lineas.find(l => l.sku === a.linea.sku);
      return {
        ...c,
        lineas: existe
          ? c.lineas.map(l => (l.sku === a.linea.sku ? { ...l, cantidad: l.cantidad + 1 } : l))
          : [...c.lineas, { ...a.linea, cantidad: 1 }],
      };
    }
    case 'quitar':
      return { ...c, lineas: c.lineas.filter(l => l.sku !== a.sku) };
    case 'cupon':
      return { ...c, cupon: a.codigo };
  }
}

export function totalCentimos(c: Carrito): number {
  const subtotal = c.lineas.reduce((s, l) => s + l.precioCentimos * l.cantidad, 0);
  return c.cupon === 'DIEZ' ? Math.round(subtotal * 0.9) : subtotal;
}

export function VistaCarrito() {
  const [carrito, despachar] = useReducer(reducir, { lineas: [], cupon: null });
  return (
    <section aria-label="Carrito">
      <button onClick={() => despachar({ tipo: 'agregar', linea: { sku: 'ZAP-1', nombre: 'Zapatillas', precioCentimos: 25990 } })}>
        Agregar zapatillas
      </button>
      <ul>
        {carrito.lineas.map(l => (
          <li key={l.sku}>
            {l.nombre} × {l.cantidad}{' '}
            <button onClick={() => despachar({ tipo: 'quitar', sku: l.sku })}>Quitar</button>
          </li>
        ))}
      </ul>
      <p>Total: {(totalCentimos(carrito) / 100).toFixed(2)}</p>
    </section>
  );
}
```

## 3. Datos del servidor: hook con cancelación y estados discriminados
```tsx
import { useEffect, useState } from 'react';

type Pedido = { id: string; estado: string; totalCentimos: number };
type Estado<T> =
  | { fase: 'cargando' }
  | { fase: 'listo'; datos: T }
  | { fase: 'error'; mensaje: string };

/** Cancela la petición si cambia el id o se desmonta el componente (sin respuestas «viejas» pisando a las nuevas). */
export function usePedido(id: string): Estado<Pedido> {
  const [estado, setEstado] = useState<Estado<Pedido>>({ fase: 'cargando' });
  useEffect(() => {
    const control = new AbortController();
    setEstado({ fase: 'cargando' });
    fetch(`/api/v1/pedidos/${encodeURIComponent(id)}`, { signal: control.signal, credentials: 'include' })
      .then(async r => {
        if (!r.ok) {
          const p = (await r.json().catch(() => ({}))) as { title?: string };
          throw new Error(p.title ?? `Error ${r.status}`);
        }
        return (await r.json()) as Pedido;
      })
      .then(datos => setEstado({ fase: 'listo', datos }))
      .catch((e: unknown) => {
        if (!control.signal.aborted) setEstado({ fase: 'error', mensaje: e instanceof Error ? e.message : 'Error' });
      });
    return () => control.abort();
  }, [id]);
  return estado;
}

export function DetallePedido({ id }: { id: string }) {
  const e = usePedido(id);
  switch (e.fase) {
    case 'cargando':
      return <p role="status">Cargando…</p>;
    case 'error':
      return <p role="alert">No se pudo cargar: {e.mensaje}</p>;
    case 'listo':
      return (
        <article>
          <h2>Pedido {e.datos.id}</h2>
          <p>Estado: {e.datos.estado}</p>
        </article>
      );
  }
}
```

## 4. Enviar sin duplicar: idempotency key y botón bloqueado
```tsx
import { useRef, useState } from 'react';

export function BotonPagar({ idPedido }: { idPedido: string }) {
  const clave = useRef<string>(crypto.randomUUID());   // misma clave en todos los reintentos de este intento de pago
  const [enviando, setEnviando] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);

  async function pagar() {
    setEnviando(true);
    try {
      const r = await fetch(`/api/v1/pedidos/${idPedido}/pagos`, {
        method: 'POST',
        headers: { 'Idempotency-Key': clave.current },
        credentials: 'include',
      });
      setMensaje(r.ok ? 'Pago registrado' : `No se pudo pagar (${r.status})`);
    } catch {
      setMensaje('Sin conexión: puedes reintentar sin riesgo de doble cobro');
    } finally {
      setEnviando(false);
    }
  }

  return (
    <>
      <button disabled={enviando} onClick={pagar}>{enviando ? 'Procesando…' : 'Pagar'}</button>
      {mensaje && <p role="status">{mensaje}</p>}
    </>
  );
}
```

## 5. Pruebas
```tsx
// nocheck — requiere @testing-library/react y un runner (Vitest/Jest)
import { render, screen, fireEvent } from '@testing-library/react';
test('agrega y quita del carrito', () => {
  render(<VistaCarrito />);
  fireEvent.click(screen.getByText('Agregar zapatillas'));
  expect(screen.getByText(/Zapatillas × 1/)).toBeInTheDocument();
});
```
Prueba el **reducer** como función pura (sin DOM) y los componentes por lo que ve el usuario (roles y textos), no por detalles internos.

## 6. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Abortar peticiones en la limpieza del efecto | Respuestas viejas que pisan a las nuevas |
| Estados discriminados (`cargando`/`listo`/`error`) | `loading && !error && data` por todas partes |
| Lógica de negocio en funciones puras (reducer) | Reglas dentro del JSX |
| `key` estable (id) en listas | Índice del arreglo como `key` en listas que cambian |
| Tokens en memoria / cookies `HttpOnly` | Tokens en `localStorage` |
| Librería de datos del servidor para caché/reintentos | Reinventar caché en cada componente |
