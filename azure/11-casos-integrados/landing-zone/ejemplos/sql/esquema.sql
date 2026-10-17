-- Direcciones de red asignadas a cada equipo. La clave primaria impide que dos solicitudes reciban el mismo bloque.
create table redes_asignadas (
    cidr        text primary key,        -- p. ej. 10.40.0.0/22
    equipo      text        not null,
    entorno     text        not null check (entorno in ('dev', 'prod')),
    asignada_en timestamptz not null default now(),
    unique (equipo, entorno)             -- un bloque por equipo y entorno
);
