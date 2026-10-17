-- Registro de subidas: la fuente de verdad del ESTADO de cada archivo (el blob solo guarda los bytes).
create table subidas (
    id             uuid primary key,
    propietario    text        not null,                 -- quién sube (subject del token)
    tipo_declarado text        not null,                 -- content-type que pidió el cliente
    tamano_max     bigint      not null,                 -- tope que se le autorizó
    estado         text        not null default 'PENDIENTE'
                   check (estado in ('PENDIENTE','SUBIDA','VALIDADA','RECHAZADA','PROCESADA','EXPIRADA')),
    motivo         text,                                 -- por qué se rechazó
    ruta_cuarentena text       not null,                 -- cuarentena/2026/10/<id>
    ruta_final     text,                                 -- validados/<id> cuando pasa la validación
    sha256         text,
    creada_en      timestamptz not null default now(),
    actualizada_en timestamptz not null default now()
);

-- El conciliador busca lo que lleva demasiado tiempo en un estado intermedio.
create index ix_subidas_estado on subidas (estado, actualizada_en);
