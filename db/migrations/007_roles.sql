-- 1. Revocar los privilegios públicos por defecto en el esquema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- 2. ROL 1: Propietario de la Base de Datos
CREATE ROLE propietario_base_datos LOGIN PASSWORD 'owner_password_secreta';

GRANT ALL PRIVILEGES ON SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO propietario_base_datos;

-- 3. ROL 2: API Lectura y Escritura
CREATE ROLE rol_api_lectura_escritura LOGIN PASSWORD 'api_password_secreta';

GRANT USAGE ON SCHEMA public TO rol_api_lectura_escritura;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO rol_api_lectura_escritura;

-- 4. ROL 3: Reportes Solo Lectura
CREATE ROLE rol_reportes_solo_lectura LOGIN PASSWORD 'reportes_password_secreta';

GRANT USAGE ON SCHEMA public TO rol_reportes_solo_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_reportes_solo_lectura;