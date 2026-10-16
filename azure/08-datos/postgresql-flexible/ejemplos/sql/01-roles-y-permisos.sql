-- PostgreSQL Flexible Server · roles SIN contraseñas (Microsoft Entra ID).
-- Ejecutar conectado a la BASE "postgres" y luego a la base de la aplicación, como administrador Entra (grupo).
-- Token de administrador:  az account get-access-token --resource-type oss-rdbms
-- psql "host=pg-modalima.postgres.database.azure.com dbname=pedidos user=DBAdmins sslmode=verify-full"

-- 1) Crear los roles de Entra (el nombre debe coincidir con la identidad en Entra ID)
--    pgaadauth_create_principal(nombre, es_administrador, es_mfa)
SELECT * FROM pgaadauth_create_principal('id-api-pedidos', false, false);          -- identidad administrada de la API
SELECT * FROM pgaadauth_create_principal('id-pipeline-migraciones', false, false); -- identidad del pipeline (dueña del esquema)
SELECT * FROM pgaadauth_create_principal('Analistas-ModaLima', false, false);      -- grupo de Entra (solo lectura)

-- Ver los roles de Entra existentes
SELECT * FROM pgaadauth_list_principals(false);

-- 2) El esquema pertenece a la identidad de migraciones; la aplicación NO es dueña de nada
CREATE SCHEMA IF NOT EXISTS ventas AUTHORIZATION "id-pipeline-migraciones";

-- 3) Permisos mínimos de la aplicación
GRANT USAGE ON SCHEMA ventas TO "id-api-pedidos";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ventas TO "id-api-pedidos";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ventas TO "id-api-pedidos";

-- Lo que cree la identidad de migraciones en el futuro hereda esos permisos automáticamente
ALTER DEFAULT PRIVILEGES FOR ROLE "id-pipeline-migraciones" IN SCHEMA ventas
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "id-api-pedidos";
ALTER DEFAULT PRIVILEGES FOR ROLE "id-pipeline-migraciones" IN SCHEMA ventas
    GRANT USAGE, SELECT ON SEQUENCES TO "id-api-pedidos";

-- 4) Analistas: solo lectura
GRANT USAGE ON SCHEMA ventas TO "Analistas-ModaLima";
GRANT SELECT ON ALL TABLES IN SCHEMA ventas TO "Analistas-ModaLima";
ALTER DEFAULT PRIVILEGES FOR ROLE "id-pipeline-migraciones" IN SCHEMA ventas
    GRANT SELECT ON TABLES TO "Analistas-ModaLima";
-- Un REVOKE de columna NO quita un permiso concedido a nivel de tabla: se retira el de tabla y se concede por columnas
REVOKE SELECT ON ventas.cliente FROM "Analistas-ModaLima";
GRANT SELECT (id, nombre, correo, creado_en) ON ventas.cliente TO "Analistas-ModaLima";   -- sin documento_identidad

-- 5) Seguridad general de la base: nadie hereda permisos por PUBLIC
REVOKE ALL ON DATABASE pedidos FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE pedidos TO "id-api-pedidos", "id-pipeline-migraciones", "Analistas-ModaLima";

-- 6) Límites por rol: protege el servidor de una consulta o conexión descontrolada
ALTER ROLE "id-api-pedidos" SET statement_timeout = '30s';
ALTER ROLE "id-api-pedidos" SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE "id-api-pedidos" CONNECTION LIMIT 60;
ALTER ROLE "Analistas-ModaLima" SET statement_timeout = '5min';
ALTER ROLE "Analistas-ModaLima" CONNECTION LIMIT 10;

-- 7) Verificación
SELECT r.rolname, r.rolcanlogin, r.rolconnlimit,
       ARRAY(SELECT b.rolname FROM pg_auth_members m JOIN pg_roles b ON b.oid = m.roleid WHERE m.member = r.oid) AS miembro_de
FROM pg_roles AS r
WHERE r.rolname NOT LIKE 'pg\_%' AND r.rolname NOT LIKE 'azure%'
ORDER BY r.rolname;

-- 8) Retirar a una identidad
-- REASSIGN OWNED BY "id-api-pedidos" TO "id-pipeline-migraciones"; DROP OWNED BY "id-api-pedidos"; DROP ROLE "id-api-pedidos";
