-- =====================================================================================
--  CONVERTIR LA BASE DE DATOS DE FERCHO EN LA DE «PINCHOS LA 17»
--  (para reutilizar el mismo proyecto de Neon en vez de crear uno nuevo)
--
--  Cómo usarlo: Neon → el proyecto → SQL Editor → pega TODO este archivo → Run.
--  ANTES: crea una copia de respaldo en Neon (Branches → Create branch). Esto NO se puede deshacer.
--
--  BORRA TODO lo de Fercho:
--    · pedidos, comandas, facturas, turnos y movimientos de caja, gastos, alertas y auditoría
--    · la carta (platos, opciones, promociones, combos), anuncios y fotos
--    · insumos, recetas, presentaciones, compras e historial del inventario
--    · TODOS los usuarios (el administrador nuevo se crea solo al reiniciar el servidor, ver abajo)
--    · historial de cambios de precio y de ingresos al sistema
--  CONSERVA: la estructura de las tablas, el registro de actualizaciones y los ajustes generales.
--  DEJA LISTO: zonas de cocina «Asador» y «Cocina», pedidos y facturas empezando en 1.
--
--  ORDEN CORRECTO (importante):
--    1. Sube a GitHub el código de Pinchos la 17 y espera a que Render lo publique.
--    2. En Render → Environment pon: ADMIN_USUARIO, ADMIN_CLAVE (del dueño nuevo) y un JWT_SECRET NUEVO.
--    3. Ejecuta este script en Neon.
--    4. En Render → Manual Deploy → «Restart service». Al arrancar crea el administrador nuevo.
--    5. Entra con ese usuario → Carta → «Cargar la carta de Pinchos la 17». Luego BORRA ADMIN_CLAVE en Render.
-- =====================================================================================
BEGIN;

-- 1) Vaciar todas las tablas de datos (menos los ajustes y el registro de actualizaciones), con contadores en 1.
--    Se hace con TRUNCATE en una sola orden para que las claves foráneas no estorben.
DO $$
DECLARE lista text;
BEGIN
  SELECT string_agg(format('%I.%I', schemaname, tablename), ', ')
    INTO lista
    FROM pg_tables
   WHERE schemaname = 'public' AND tablename NOT IN ('ajustes', 'migraciones');
  EXECUTE 'TRUNCATE ' || lista || ' RESTART IDENTITY CASCADE';
END $$;

-- 2) Zonas de cocina de Pinchos la 17
INSERT INTO zonas (nombre, color, orden) VALUES ('Asador', '#e2231a', 1), ('Cocina', '#ffb000', 2);

-- 3) Ajustes que eran del local anterior
UPDATE ajustes SET valor = '' WHERE clave IN ('local_lat', 'local_lng');          -- ubicación del local: marcar la nueva
UPDATE ajustes SET valor = 'pantallas' WHERE clave = 'modo_cocina';               -- empezar con pantallas; cambiar en Ajustes si usan impresoras

COMMIT;

-- Comprobación: todo en 0 menos las 2 zonas
SELECT (SELECT count(*) FROM usuarios) AS usuarios, (SELECT count(*) FROM platos) AS platos,
       (SELECT count(*) FROM insumos)  AS insumos,  (SELECT count(*) FROM pedidos) AS pedidos,
       (SELECT count(*) FROM facturas) AS facturas, (SELECT string_agg(nombre, ', ' ORDER BY orden) FROM zonas) AS zonas;
