-- Migración 14: productos de compra-venta (gaseosas, cervezas…) con costo fijo, y opción de costo de producción manual para los platos.
-- · platos.tipo: 'plato' (se prepara: su costo sale de la receta) | 'producto' (se compra hecho y se vende igual: su costo es el de compra).
-- · platos.costo_fijo: costo por unidad. En un producto es el costo de compra; en un plato se usa solo si el ajuste costo_platos = 'manual'.
-- · pedido_items.costo_fijo: copia del costo fijo al vender (NULL = el costo sale de las recetas, como siempre).
-- · movimientos_inventario.costo_aparte: salida de inventario de un producto con costo fijo (baja existencias, pero su costo ya va en costo_fijo).
-- · ajuste costo_platos: 'receta' (el sistema calcula el costo con los insumos) | 'manual' (el dueño escribe el costo de producción).
-- Idempotente: se puede correr varias veces.
ALTER TABLE platos ADD COLUMN IF NOT EXISTS tipo varchar(10) NOT NULL DEFAULT 'plato';
ALTER TABLE platos ADD COLUMN IF NOT EXISTS costo_fijo numeric(12,2);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platos_tipo_valido') THEN
    ALTER TABLE platos ADD CONSTRAINT platos_tipo_valido CHECK (tipo IN ('plato', 'producto'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platos_costo_fijo_valido') THEN
    ALTER TABLE platos ADD CONSTRAINT platos_costo_fijo_valido CHECK (costo_fijo IS NULL OR costo_fijo >= 0);
  END IF;
END $$;
ALTER TABLE pedido_items ADD COLUMN IF NOT EXISTS costo_fijo numeric(12,2);
ALTER TABLE movimientos_inventario ADD COLUMN IF NOT EXISTS costo_aparte boolean NOT NULL DEFAULT false;
INSERT INTO ajustes (clave, valor) VALUES ('costo_platos', 'receta') ON CONFLICT (clave) DO NOTHING;
-- Lo que ya está en la carta y no pasa por cocina (bebidas) se marca como producto, para que el dueño le ponga su costo de compra
UPDATE platos p SET tipo = 'producto'
 WHERE p.tipo = 'plato' AND NOT p.es_promo
   AND NOT EXISTS (SELECT 1 FROM plato_zonas z WHERE z.plato_id = p.id)
   AND NOT EXISTS (SELECT 1 FROM plato_combo c WHERE c.promo_id = p.id);
