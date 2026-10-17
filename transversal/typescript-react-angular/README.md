# Transversal · TypeScript, React y Angular para microservicios

El frontend es el cliente más exigente de tus microservicios: necesita respuestas a la medida de cada pantalla, tolerar fallos de red, no duplicar operaciones y mantener la seguridad del usuario. Este módulo cubre **TypeScript** (los tipos como contrato), **React** y **Angular** (las dos opciones más comunes) y cómo se **integran** con un backend de microservicios.

## 1. Qué es

**Analogía:** la vitrina y el mostrador de una tienda: el cliente solo ve eso, pero detrás hay bodegas (servicios). Un buen mostrador (BFF) junta lo que la vitrina necesita y no deja que el cliente entre a la bodega.

```
 Navegador (React o Angular, TypeScript)
   │ HTTPS · cookie de sesión HttpOnly (o token en memoria) · X-Correlation-Id · Idempotency-Key
   ▼
 BFF / API gateway  ── agrega y adapta respuestas por pantalla, maneja el login OIDC
   ├─► catálogo     ├─► pedidos     ├─► pagos     (microservicios)
```

## 2. Contenido
| Archivo | Temas |
|---|---|
| [TypeScript](typescript.md) | Tipos, uniones discriminadas, genéricos, *utility types*, validación de `unknown`, `fetch` con timeout e idempotencia, exhaustividad |
| [React](react.md) | Hooks, `useReducer` para el carrito, hook de datos con cancelación, botón de pago idempotente, pruebas |
| [Angular](angular.md) | Standalone, signals, `HttpClient` e interceptores, búsqueda con RxJS (`switchMap`), formularios tipados, *guards* |

## 3. React o Angular
| Criterio | React | Angular |
|---|---|---|
| Tipo | Biblioteca de UI + ecosistema a elegir | Framework completo y opinado |
| Estado | Hooks, reducers, librerías externas | Signals + RxJS + servicios |
| Datos del servidor | Librería de datos (caché, reintentos) | `HttpClient` + RxJS / recursos |
| Formularios | Librerías o controlados a mano | Formularios reactivos tipados incluidos |
| Inyección de dependencias | No nativa (contexto) | Nativa |
| Curva | Suave al inicio, decisiones después | Más conceptos al inicio, menos decisiones |
| Encaja con | Equipos que quieren elegir piezas, productos variados | Equipos grandes, aplicaciones empresariales homogéneas |

## 4. Integración con microservicios
| Tema | Práctica recomendada |
|---|---|
| **BFF** | Un backend por tipo de cliente que agrega llamadas y adapta formatos; el navegador no habla con 10 servicios |
| **Autenticación** | OIDC con *Authorization Code + PKCE*; mejor aún, el BFF guarda los tokens y el navegador solo tiene una cookie `HttpOnly`, `Secure`, `SameSite` |
| **Contratos** | Tipos generados desde el OpenAPI de cada servicio/BFF en el build |
| **Errores** | Interpretar ProblemDetail (`title`, `status`, `detail`) y mostrar mensajes útiles |
| **Reintentos** | Solo en operaciones idempotentes; `POST` con `Idempotency-Key` |
| **Timeouts y cancelación** | `AbortController` / `switchMap`; nunca dejar peticiones colgadas |
| **Paginación** | Por cursor (`siguiente`) para listas largas |
| **Trazas** | `X-Correlation-Id` (o `traceparent`) en cada petición |
| **CORS** | Mejor evitarlo sirviendo front y BFF bajo el mismo dominio; si no, orígenes explícitos |
| **Rendimiento** | Carga diferida de rutas, imágenes optimizadas, caché HTTP de recursos estáticos |

## 5. Seguridad
| Riesgo | Control |
|---|---|
| XSS | Los frameworks escapan por defecto; no uses `dangerouslySetInnerHTML` / `bypassSecurityTrust…` con datos de usuarios; CSP estricta |
| Robo de tokens | Nada de tokens en `localStorage`; cookies `HttpOnly` vía BFF o tokens solo en memoria |
| CSRF (con cookies) | `SameSite=Lax/Strict` + token anti-CSRF en operaciones de escritura |
| Autorización | Siempre en el backend; ocultar un botón no protege nada |
| Dependencias | Bloqueo de versiones (lockfile) y auditoría en CI |
| Secretos | El frontend no guarda secretos: todo lo que se envía al navegador es público |

## 6. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| `strict: true` y tipos generados del contrato | `any` y DTO copiados a mano |
| Estados de carga/error explícitos | Pantallas en blanco cuando falla un servicio |
| BFF por tipo de cliente | El navegador orquestando 10 servicios |
| `Idempotency-Key` en pagos y altas | Doble clic = doble pedido |
| Cancelar peticiones obsoletas | Resultados de búsquedas viejas apareciendo al final |
| Accesibilidad (roles, etiquetas, foco) | Interfaces solo para ratón |

## 7. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El doble pedido | En ModaLima, el doble clic en «Pagar» creaba dos pedidos | Botón deshabilitado + `Idempotency-Key` |
| La búsqueda que retrocedía | Resultados de «zap» aparecían después de «zapatillas» | Cancelar con `AbortController` o `switchMap` |
| El token robado | Un script de terceros leyó el token de `localStorage` en Café Andino | Cookie `HttpOnly` vía BFF + CSP |
| El campo renombrado | El backend cambió `total` por `totalCentimos` y el front mostró `NaN` | Tipos generados del OpenAPI y validación en el borde |
| 14 llamadas para una pantalla | La página de inicio llamaba a 14 servicios | BFF que agrega |

**Siguiente:** [TypeScript](typescript.md) · [React](react.md) · [Angular](angular.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
