-- Azure SQL Database · usuarios y roles SIN contraseñas (Entra ID).
-- Ejecutar conectado a LA BASE (no a master) como administrador Entra (grupo DBAdmins).
-- Los nombres entre corchetes son los nombres de las identidades en Entra ID
-- (identidad administrada = nombre del recurso; grupo = nombre del grupo).

-- 1) Aplicación de pedidos: lee y escribe, y ejecuta procedimientos del esquema ventas
CREATE USER [id-api-pedidos] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [id-api-pedidos];
ALTER ROLE db_datawriter ADD MEMBER [id-api-pedidos];
GRANT EXECUTE ON SCHEMA::ventas TO [id-api-pedidos];

-- 2) Pipeline de migraciones: puede cambiar el esquema, pero la app NO
CREATE USER [id-pipeline-migraciones] FROM EXTERNAL PROVIDER;
ALTER ROLE db_ddladmin ADD MEMBER [id-pipeline-migraciones];
ALTER ROLE db_datareader ADD MEMBER [id-pipeline-migraciones];
ALTER ROLE db_datawriter ADD MEMBER [id-pipeline-migraciones];

-- 3) Analistas: solo lectura, y sin ver columnas sensibles (ver 02-seguridad-datos.sql)
CREATE USER [Analistas-ModaLima] FROM EXTERNAL PROVIDER;      -- grupo de Entra
ALTER ROLE db_datareader ADD MEMBER [Analistas-ModaLima];
DENY SELECT (documento_identidad) ON ventas.cliente TO [Analistas-ModaLima];

-- 4) Rol propio con permisos exactos (mejor que roles amplios)
CREATE ROLE rol_servicio_facturacion;
GRANT SELECT ON OBJECT::ventas.pedido TO rol_servicio_facturacion;
GRANT SELECT, INSERT ON OBJECT::ventas.factura TO rol_servicio_facturacion;
GRANT EXECUTE ON OBJECT::ventas.sp_emitir_factura TO rol_servicio_facturacion;
CREATE USER [id-api-facturacion] FROM EXTERNAL PROVIDER;
ALTER ROLE rol_servicio_facturacion ADD MEMBER [id-api-facturacion];

-- 5) Verificación: qué usuarios y roles existen
SELECT dp.name AS usuario, dp.type_desc AS tipo, r.name AS rol
FROM sys.database_principals AS dp
LEFT JOIN sys.database_role_members AS drm ON drm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals AS r ON r.principal_id = drm.role_principal_id
WHERE dp.type IN ('E', 'X', 'S', 'U')      -- E/X = Entra, S = SQL, U = Windows
ORDER BY dp.name, r.name;

-- 6) Revocar acceso de una identidad (cuando se retira un servicio)
-- DROP USER [id-api-pedidos];
