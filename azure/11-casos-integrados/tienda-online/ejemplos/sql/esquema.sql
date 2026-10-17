-- Esquema mínimo de la tienda (PostgreSQL). Pedido + bandeja de salida (outbox) + bandeja de entrada (idempotencia).

create table pedidos (
    id         uuid primary key,
    cliente_id text           not null,
    total      numeric(12, 2) not null check (total >= 0),
    estado     text           not null default 'CREADO',
    creado_en  timestamptz    not null default now()
);

-- Bandeja de salida: se escribe en la MISMA transacción que el pedido; un proceso aparte la publica.
create table bandeja_salida (
    id           bigserial primary key,
    tipo         text        not null,          -- p. ej. 'pedido.creado'
    clave        text        not null,          -- id del agregado (pedido) -> MessageId / SessionId
    carga        text        not null,          -- JSON del evento
    creado_en    timestamptz not null default now(),
    publicado_en timestamptz
);

create index ix_bandeja_pendientes on bandeja_salida (id) where publicado_en is null;

-- Bandeja de entrada: un mensaje (MessageId) se procesa UNA sola vez aunque llegue repetido.
create table mensajes_procesados (
    id_mensaje   text primary key,
    procesado_en timestamptz not null default now()
);

-- Limpieza periódica (programada): lo ya publicado hace más de 7 días y los mensajes procesados antiguos
-- delete from bandeja_salida where publicado_en < now() - interval '7 days';
-- delete from mensajes_procesados where procesado_en < now() - interval '14 days';
