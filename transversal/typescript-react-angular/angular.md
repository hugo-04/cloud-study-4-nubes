# Transversal · Angular para frontends de microservicios

Angular es un framework completo (componentes, inyección de dependencias, enrutador, formularios, cliente HTTP, pruebas) con TypeScript de serie. En versiones recientes: **componentes *standalone***, **signals** para el estado reactivo, `inject()` y control de flujo `@if`/`@for` en plantillas. Versión objetivo: **Angular 20** *(verifica)*.

## 1. Piezas
| Pieza | Para qué | Regla |
|---|---|---|
| Componente *standalone* | Vista + lógica, declara sus importaciones | Pequeño y con una responsabilidad |
| **Signals** (`signal`, `computed`, `effect`) | Estado local y derivado, detección de cambios fina | `computed` para derivar, no duplicar estado |
| Servicios + `inject()` | Lógica compartida y acceso a APIs | `providedIn: 'root'` |
| `HttpClient` + interceptores funcionales | Llamadas al backend, cabeceras, errores | Un interceptor para auth, otro para correlación |
| RxJS | Flujos: búsqueda con *debounce*, cancelación | `switchMap` cancela lo anterior |
| Formularios reactivos | Validación tipada | `FormBuilder.nonNullable` |
| Enrutador + *guards* | Navegación y protección | *Guards* funcionales |

## 2. Servicio de API con HttpClient
```ts
// archivo: catalogo-api.ts
import { HttpClient, HttpErrorResponse, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, catchError, map, throwError, timeout } from 'rxjs';

export interface Producto { sku: string; nombre: string; precioCentimos: number }
export interface Pagina<T> { elementos: T[]; siguiente: string | null }
export class ErrorApi extends Error {
  constructor(readonly status: number, readonly titulo: string) { super(titulo); }
}

@Injectable({ providedIn: 'root' })
export class CatalogoApi {
  private readonly http = inject(HttpClient);

  buscar(texto: string, cursor: string | null = null): Observable<Pagina<Producto>> {
    let params = new HttpParams().set('q', texto);
    if (cursor) params = params.set('cursor', cursor);
    return this.http.get<Pagina<Producto>>('/api/v1/productos', { params }).pipe(
      timeout(5000),
      catchError((e: unknown) => {
        const status = e instanceof HttpErrorResponse ? e.status : 0;
        const titulo = e instanceof HttpErrorResponse ? (e.error?.title ?? e.statusText) : 'Tiempo agotado';
        return throwError(() => new ErrorApi(status, titulo));
      }),
    );
  }

  precioTotal(skus: string[]): Observable<number> {
    return this.http.post<{ totalCentimos: number }>('/api/v1/precios', { skus }).pipe(map(r => r.totalCentimos));
  }
}
```

## 3. Interceptor funcional: id de correlación y sesión
```ts
import { HttpInterceptorFn } from '@angular/common/http';

/** Cada petición lleva un id de correlación para seguirla en las trazas del backend. */
export const correlacionInterceptor: HttpInterceptorFn = (req, next) => {
  const id = crypto.randomUUID();
  return next(req.clone({ setHeaders: { 'X-Correlation-Id': id }, withCredentials: true }));
};

// app.config.ts:
// provideHttpClient(withInterceptors([correlacionInterceptor]))
```

## 4. Búsqueda con signals + RxJS (debounce y cancelación)
```ts
import { Component, computed, inject, signal } from '@angular/core';
import { toObservable, toSignal } from '@angular/core/rxjs-interop';
import { catchError, debounceTime, distinctUntilChanged, filter, map, of, startWith, switchMap } from 'rxjs';
import { CatalogoApi, Producto } from './catalogo-api';

type Vista = { fase: 'inicio' } | { fase: 'cargando' } | { fase: 'listo'; productos: Producto[] } | { fase: 'error'; mensaje: string };

@Component({
  selector: 'ml-buscador',
  standalone: true,
  template: `
    <input [value]="texto()" (input)="texto.set($any($event.target).value)" placeholder="Buscar" />
    @switch (vista().fase) {
      @case ('cargando') { <p role="status">Buscando…</p> }
      @case ('error') { <p role="alert">No se pudo buscar</p> }
    }
    <ul>
      @for (p of productos(); track p.sku) { <li>{{ p.nombre }}</li> }
    </ul>
    <p>{{ cantidad() }} resultados</p>
  `,
})
export class BuscadorComponent {
  private readonly api = inject(CatalogoApi);
  readonly texto = signal('');

  /** switchMap cancela la búsqueda anterior si el usuario sigue escribiendo. */
  readonly vista = toSignal(
    toObservable(this.texto).pipe(
      debounceTime(300),
      map(t => t.trim()),
      distinctUntilChanged(),
      filter(t => t.length >= 2),
      switchMap(t =>
        this.api.buscar(t).pipe(
          map((r): Vista => ({ fase: 'listo', productos: r.elementos })),
          startWith<Vista>({ fase: 'cargando' }),
          catchError(() => of<Vista>({ fase: 'error', mensaje: 'error' })),
        ),
      ),
    ),
    { initialValue: { fase: 'inicio' } as Vista },
  );

  readonly productos = computed(() => {
    const v = this.vista();
    return v.fase === 'listo' ? v.productos : [];
  });
  readonly cantidad = computed(() => this.productos().length);
}
```
(El bloque importa `./catalogo-api`, que es el servicio de la sección 2.)

## 5. Formulario reactivo tipado y *guard*
```ts
import { Component, inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

@Component({
  selector: 'ml-direccion',
  standalone: true,
  imports: [ReactiveFormsModule],
  template: `
    <form [formGroup]="form" (ngSubmit)="guardar()">
      <input formControlName="calle" />
      <input formControlName="distrito" />
      <button [disabled]="form.invalid">Guardar</button>
    </form>
  `,
})
export class DireccionComponent {
  private readonly fb = inject(FormBuilder);
  readonly form = this.fb.nonNullable.group({
    calle: ['', [Validators.required, Validators.maxLength(120)]],
    distrito: ['', Validators.required],
  });

  guardar(): void {
    const { calle, distrito } = this.form.getRawValue();   // tipado: string, string
    console.log('guardar', calle, distrito);
  }
}

/** Guard funcional: la verdad la tiene el backend; esto solo mejora la experiencia. */
export const sesionGuard: CanActivateFn = () => {
  const router = inject(Router);
  const haySesion = document.cookie.includes('sesion_presente=1');
  return haySesion ? true : router.parseUrl('/ingresar');
};
```

## 6. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Signals para estado de la vista, RxJS para flujos asíncronos | Suscripciones manuales sin cancelar |
| `switchMap` en búsquedas | `mergeMap` que deja llegar respuestas viejas |
| `track` en `@for` | Listas sin identidad estable |
| Interceptores para cabeceras comunes | Repetir cabeceras en cada servicio |
| Formularios tipados (`nonNullable`) | `any` en formularios |
| La autorización real en el backend | Confiar en un *guard* para la seguridad |
