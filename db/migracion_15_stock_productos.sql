-- Migración 15: el negocio también es tienda. Inventario dividido en materias primas y productos, con mínimos y máximos.
-- · insumos.tipo: 'materia_prima' (se usa para preparar platos) | 'producto' (se vende tal cual: gaseosas, cervezas…).
-- · insumos.stock_min / stock_max: tope mínimo (al llegar ahí hay que pedir) y máximo (hasta dónde pedir).
-- · platos.insumo_id: la existencia propia de un producto de la carta; al venderlo baja 1 unidad (receta automática de 1 u).
-- Nada de esto se muestra a los clientes. Idempotente.
ALTER TABLE insumos ADD COLUMN IF NOT EXISTS tipo varchar(15) NOT NULL DEFAULT 'materia_prima';
ALTER TABLE insumos ADD COLUMN IF NOT EXISTS stock_min numeric(12,2);
ALTER TABLE insumos ADD COLUMN IF NOT EXISTS stock_max numeric(12,2);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'insumos_tipo_valido') THEN
    ALTER TABLE insumos ADD CONSTRAINT insumos_tipo_valido CHECK (tipo IN ('materia_prima', 'producto'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'insumos_topes_validos') THEN
    ALTER TABLE insumos ADD CONSTRAINT insumos_topes_validos CHECK ((stock_min IS NULL OR stock_min >= 0) AND (stock_max IS NULL OR stock_max > 0)
      AND (stock_min IS NULL OR stock_max IS NULL OR stock_max >= stock_min));
  END IF;
END $$;
ALTER TABLE platos ADD COLUMN IF NOT EXISTS insumo_id int REFERENCES insumos(id);
-- Productos que ya tenían una receta de una sola línea: esa es su existencia
UPDATE platos p SET insumo_id = r.insumo_id
  FROM (SELECT plato_id, min(insumo_id) AS insumo_id FROM recetas GROUP BY plato_id HAVING count(*) = 1) r
 WHERE p.tipo = 'producto' AND p.insumo_id IS NULL AND r.plato_id = p.id;
-- Productos sin receta: se les crea su existencia (en unidades, empieza en 0) y su receta de 1 unidad
WITH nuevos AS (
  INSERT INTO insumos (codigo, nombre, cantidad, unidad, costo_unitario, tipo)
  SELECT 'PROD-' || p.id, left(p.nombre, 80), 0, 'u', coalesce(p.costo_fijo, 0), 'producto' FROM platos p
   WHERE p.tipo = 'producto' AND p.activo AND p.insumo_id IS NULL AND NOT EXISTS (SELECT 1 FROM recetas r WHERE r.plato_id = p.id)
  ON CONFLICT (codigo) DO NOTHING RETURNING id, codigo)
UPDATE platos p SET insumo_id = n.id FROM nuevos n WHERE n.codigo = 'PROD-' || p.id;
INSERT INTO recetas (plato_id, insumo_id, cantidad)
SELECT p.id, p.insumo_id, 1 FROM platos p
 WHERE p.insumo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM recetas r WHERE r.plato_id = p.id);
UPDATE insumos i SET tipo = 'producto' FROM platos p WHERE p.insumo_id = i.id AND i.tipo <> 'producto';
