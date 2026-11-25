-- =====================================================================
-- Pinchos la 17 · DML (lenguaje de manipulación de datos)
-- Se ejecuta sobre la base con la carta cargada y los usuarios dueno, caja1 y cocina1.
-- Motor: PostgreSQL. Cada bloque está probado; sus resultados están en el PDF.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. [INSERT] Insumos del inventario
-- Materias primas en su unidad base (g, ml o u), con costo por unidad y porcentaje de merma. Los productos de tienda (gaseosas, cervezas) ya tienen su propia existencia, creada al cargar la carta.
-- ---------------------------------------------------------------------
INSERT INTO insumos (codigo, nombre, cantidad, unidad, costo_unitario, merma_pct) VALUES
  ('CAR', 'Carne de res',              10000, 'g', 34,   0),
  ('POL', 'Pechuga de pollo',           8000, 'g', 22,   0),
  ('CHU', 'Chunchullo',                 3000, 'g', 18,  15),
  ('CEB', 'Cebolla',                    5000, 'g',  3,  10),
  ('ARR', 'Arroz',                      5000, 'g',  4,   0)
RETURNING id, codigo, nombre, cantidad, unidad, merma_pct;

-- ---------------------------------------------------------------------
-- 2. [INSERT] Presentación de compra
-- Cómo se compra un insumo: el bulto de arroz trae 25.000 g.
-- ---------------------------------------------------------------------
INSERT INTO presentaciones (insumo_id, nombre, cantidad_base)
SELECT id, 'Bulto 25 kg', 25000 FROM insumos WHERE codigo = 'ARR'
RETURNING id, nombre, cantidad_base;

-- ---------------------------------------------------------------------
-- 3. [INSERT] Recetas de los platos (INSERT … SELECT)
-- Cuánto gasta una porción. Se insertan buscando el plato y el insumo por su nombre y código.
-- ---------------------------------------------------------------------
INSERT INTO recetas (plato_id, insumo_id, cantidad)
SELECT p.id, s.id, r.cantidad
FROM (VALUES ('Pincho mixto', 'CAR', 60), ('Pincho mixto', 'POL', 60), ('Pincho mixto', 'CEB', 20),
             ('Pincho solo carne', 'CAR', 120), ('Pincho solo carne', 'CEB', 20),
             ('Pincho de carne con chunchullo', 'CAR', 70), ('Pincho de carne con chunchullo', 'CHU', 60)) AS r(plato, codigo, cantidad)
JOIN platos p ON p.nombre = r.plato AND p.activo JOIN insumos s ON s.codigo = r.codigo
RETURNING plato_id, insumo_id, cantidad;

-- ---------------------------------------------------------------------
-- 4. [INSERT] Insumos de una opción (adicional de arroz)
-- El adicional «Arroz» de todos los platos gasta 120 g de arroz: solo se descuenta si el cliente lo elige.
-- ---------------------------------------------------------------------
INSERT INTO opcion_receta (opcion_id, insumo_id, cantidad)
SELECT o.id, (SELECT id FROM insumos WHERE codigo = 'ARR'), 120
FROM opciones o JOIN opcion_grupos g ON g.id = o.grupo_id
WHERE g.nombre = 'Adicionales' AND o.nombre = 'Arroz';
SELECT count(*) AS opciones_de_arroz_con_receta FROM opcion_receta;

-- ---------------------------------------------------------------------
-- 5. [INSERT] Anuncio publicitario
-- Banner del menú del cliente ligado a un plato.
-- ---------------------------------------------------------------------
INSERT INTO anuncios (titulo, texto, plato_id)
VALUES ('Martes de pinchos', '2 pinchos mixtos + Club Colombia', (SELECT id FROM platos WHERE nombre = 'Pincho mixto' AND activo))
RETURNING id, titulo, plato_id;

-- ---------------------------------------------------------------------
-- 6. [UPDATE] Producto de tienda: precio, costo de compra, existencia y topes
-- Las bebidas se cargaron en $0 y agotadas. Se les pone precio de venta y costo de compra; su existencia propia recibe 48 unidades, con mínimo 12 y máximo 48. El cambio de precio queda en la bitácora.
-- ---------------------------------------------------------------------
WITH antes AS (SELECT id, nombre, precio FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo)
UPDATE platos p SET precio = 5000, costo_fijo = 2800, agotado = FALSE FROM antes a WHERE p.id = a.id
RETURNING p.nombre, p.tipo, a.precio AS precio_antes, p.precio AS precio_nuevo, p.costo_fijo AS costo_compra, p.agotado;

UPDATE insumos SET cantidad = 48, costo_unitario = 2800, stock_min = 12, stock_max = 48
WHERE id = (SELECT insumo_id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo)
RETURNING codigo, nombre, tipo, cantidad, stock_min, stock_max;

INSERT INTO cambios_precio (tipo, ref_id, nombre, campo, antes, despues, usuario_id)
SELECT 'plato', id, nombre, 'precio', '0', '5000', (SELECT id FROM usuarios WHERE usuario = 'dueno')
FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo;

-- ---------------------------------------------------------------------
-- 7. [UPDATE] Compra de inventario: entra pollo y se recalcula el costo promedio
-- Compra de 5.000 g de pollo por $115.000. Se registra la compra, su movimiento de entrada y el nuevo costo promedio ponderado.
-- ---------------------------------------------------------------------
BEGIN;
WITH compra AS (
  INSERT INTO compras_inventario (insumo_id, cantidad_base, costo_total, proveedor, usuario_id)
  SELECT id, 5000, 115000, 'Avícola Santander', (SELECT id FROM usuarios WHERE usuario = 'dueno')
  FROM insumos WHERE codigo = 'POL' RETURNING id, insumo_id, cantidad_base, costo_total)
INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, delta, motivo, compra_id, usuario_id)
SELECT insumo_id, 'entrada', cantidad_base, cantidad_base, 'Compra', id, (SELECT id FROM usuarios WHERE usuario = 'dueno') FROM compra;

UPDATE insumos SET
  costo_unitario = round((cantidad * costo_unitario + 115000) / (cantidad + 5000), 4),   -- promedio ponderado
  cantidad       = cantidad + 5000
WHERE codigo = 'POL'
RETURNING codigo, cantidad, costo_unitario;
COMMIT;

-- ---------------------------------------------------------------------
-- 8. [INSERT] Abrir el turno de caja
-- Sin turno abierto no se puede cobrar. Un índice único impide abrir dos turnos a la vez.
-- ---------------------------------------------------------------------
INSERT INTO turnos_caja (abierto_por, monto_apertura) VALUES ((SELECT id FROM usuarios WHERE usuario = 'caja1'), 100000)
RETURNING id, monto_apertura, abierto_en::time(0);

-- ---------------------------------------------------------------------
-- 9. [INSERT] Pedido #1: mesa 4 (2 pinchos mixtos con arroz + 1 Club Colombia)
-- El pedido y sus ítems. La opción elegida se guarda como copia (JSONB) con su precio del momento.
-- ---------------------------------------------------------------------
INSERT INTO pedidos (tipo, mesa, total) VALUES ('mesa', '4', 0) RETURNING numero, estado;

INSERT INTO pedido_items (pedido_id, plato_id, nombre, precio_unit, cantidad, opciones) VALUES
 ((SELECT id FROM pedidos WHERE numero = 1), (SELECT id FROM platos WHERE nombre = 'Pincho mixto' AND activo), 'Pincho mixto (Arroz)', 8000 + 1500, 2,
  jsonb_build_array(jsonb_build_object('id', (SELECT o.id FROM opciones o JOIN opcion_grupos g ON g.id = o.grupo_id JOIN platos p ON p.id = g.plato_id WHERE p.nombre = 'Pincho mixto' AND o.nombre = 'Arroz' AND p.activo), 'grupo', 'Adicionales', 'nombre', 'Arroz', 'extra', 1500))),
 ((SELECT id FROM pedidos WHERE numero = 1), (SELECT id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo), 'Club Colombia botella 330 ml', 5000, 1, '[]');

UPDATE pedidos SET total = (SELECT sum(precio_unit * cantidad) FROM pedido_items WHERE pedido_id = (SELECT id FROM pedidos WHERE numero = 1))
WHERE numero = 1 RETURNING numero, mesa, total;

-- ---------------------------------------------------------------------
-- 10. [SELECT] Existencias ANTES de que la cocina empiece
-- Fotografía del inventario con el pedido #1 confirmado pero sin preparar.
-- ---------------------------------------------------------------------
SELECT codigo, nombre, tipo, cantidad AS existencia, unidad FROM insumos
WHERE tipo = 'materia_prima' OR id = (SELECT insumo_id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo) ORDER BY tipo, codigo;

-- ---------------------------------------------------------------------
-- 11. [UPDATE] La cocina empieza el pedido #1: se descuenta el inventario
-- Una sola sentencia: calcula el consumo (receta + adicional, con merma), registra cada salida ligada al pedido y baja las existencias. La bandera inventario_descontado impide descontar dos veces.
-- ---------------------------------------------------------------------
WITH items AS (
       SELECT coalesce(cb.plato_id, it.plato_id) AS plato_id, it.cantidad * coalesce(cb.cantidad, 1) AS qty, it.sin
       FROM pedido_items it LEFT JOIN plato_combo cb ON cb.promo_id = it.plato_id
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 1)),
     base AS (                                   -- receta del plato
       SELECT r.insumo_id, r.cantidad * i.qty AS q
       FROM items i JOIN recetas r ON r.plato_id = i.plato_id JOIN insumos s ON s.id = r.insumo_id
       WHERE NOT (s.nombre = ANY (i.sin))),
     opc AS (                                    -- insumos de las opciones elegidas (adicionales)
       SELECT r.insumo_id, r.cantidad * it.cantidad AS q
       FROM pedido_items it CROSS JOIN LATERAL jsonb_array_elements(it.opciones) o
       JOIN opcion_receta r ON r.opcion_id = (o->>'id')::int
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 1)),
     consumo AS (                                -- total por insumo, con la merma
       SELECT x.insumo_id, round(sum(x.q) / (1 - s.merma_pct / 100.0), 2) AS qty, s.cantidad AS stock
       FROM (SELECT * FROM base UNION ALL SELECT * FROM opc) x JOIN insumos s ON s.id = x.insumo_id
       GROUP BY x.insumo_id, s.merma_pct, s.cantidad),
     mov AS (
       INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, delta, motivo, pedido_id, usuario_id)
       SELECT insumo_id, 'salida', qty, -LEAST(stock, qty), 'Pedido en preparación', (SELECT id FROM pedidos WHERE numero = 1), (SELECT id FROM usuarios WHERE usuario = 'cocina1')
       FROM consumo RETURNING insumo_id, cantidad)
UPDATE insumos s SET cantidad = GREATEST(s.cantidad - m.cantidad, 0)
FROM mov m WHERE s.id = m.insumo_id;

UPDATE pedidos SET estado = 'preparacion', preparacion_en = now(), inventario_descontado = TRUE
WHERE numero = 1 AND NOT inventario_descontado;

-- ---------------------------------------------------------------------
-- 12. [SELECT] Existencias ANTES y DESPUÉS de cerrar el pedido #1
-- Cebolla: 2 × 20 g ÷ (1 − 0,10) = 44,44 g. Arroz: 2 × 120 g del adicional. El pollo incluye la compra anterior.
-- ---------------------------------------------------------------------
-- «Antes» = existencia actual + lo que salió por este pedido
SELECT s.nombre AS insumo, s.unidad,
       s.cantidad - coalesce(sum(m.delta), 0) AS antes,
       coalesce(-sum(m.delta), 0)             AS salio,
       s.cantidad                             AS despues
FROM insumos s LEFT JOIN movimientos_inventario m ON m.insumo_id = s.id AND m.pedido_id IN ((SELECT id FROM pedidos WHERE numero = 1))
WHERE s.tipo = 'materia_prima' OR s.id = (SELECT insumo_id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo)
GROUP BY s.id ORDER BY s.tipo, s.codigo;

-- ---------------------------------------------------------------------
-- 13. [UPDATE] Pedido #1 listo y entregado
-- Cambios de estado del pedido.
-- ---------------------------------------------------------------------
UPDATE pedidos SET estado = 'listo', listo_en = now(), zonas_listas = TRUE WHERE numero = 1;
UPDATE pedidos SET estado = 'entregado' WHERE numero = 1 RETURNING numero, estado;

-- ---------------------------------------------------------------------
-- 14. [UPDATE] Cobro del pedido #1 (transacción)
-- Bloqueo, factura con número consecutivo y pedido ligado a su venta, todo o nada.
-- ---------------------------------------------------------------------
BEGIN;
-- 1) Bloquear los pedidos: si otro cajero intenta cobrarlos al tiempo, espera aquí
SELECT numero, total, pagado, estado FROM pedidos WHERE id IN ((SELECT id FROM pedidos WHERE numero = 1)) ORDER BY numero FOR UPDATE;

-- 2) Crear la venta (factura) con el siguiente número consecutivo y la copia de lo cobrado
INSERT INTO facturas (numero, turno_id, cajero_id, cajero, pedido_ids, numeros_pedido, tipo, mesa,
                      items, total, metodo_pago, recibido, vueltos)
SELECT (SELECT coalesce(max(numero), 0) + 1 FROM facturas), (SELECT id FROM turnos_caja WHERE cerrado_en IS NULL), (SELECT id FROM usuarios WHERE usuario = 'caja1'), 'caja1',
       array_agg(p.id ORDER BY p.numero), array_agg(p.numero ORDER BY p.numero), min(p.tipo), min(p.mesa),
       (SELECT jsonb_agg(jsonb_build_object('nombre', it.nombre, 'cantidad', it.cantidad, 'precio_unit', it.precio_unit, 'sin', it.sin) ORDER BY it.id)
          FROM pedido_items it WHERE it.pedido_id IN ((SELECT id FROM pedidos WHERE numero = 1))),
       sum(p.total), 'efectivo', 30000, 30000 - sum(p.total)
FROM pedidos p WHERE p.id IN ((SELECT id FROM pedidos WHERE numero = 1)) AND NOT p.pagado AND p.estado <> 'cancelado'
RETURNING numero AS factura, numeros_pedido AS pedidos, total, recibido, vueltos;

-- 3) Marcar los pedidos como pagados y ligarlos a su venta (pedidos.factura_id → facturas.id)
UPDATE pedidos SET pagado = TRUE, pagado_en = now(), turno_id = (SELECT id FROM turnos_caja WHERE cerrado_en IS NULL), metodo_pago = 'efectivo',
       factura_id = (SELECT max(id) FROM facturas)
WHERE id IN ((SELECT id FROM pedidos WHERE numero = 1)) AND NOT pagado
RETURNING numero, pagado, factura_id;
COMMIT;

-- ---------------------------------------------------------------------
-- 15. [SELECT] Las existencias NO cambian al cobrar
-- Cerrar (entregar y cobrar) no vuelve a descontar: el inventario sigue igual que después de la cocina.
-- ---------------------------------------------------------------------
SELECT codigo, nombre, tipo, cantidad AS existencia, unidad FROM insumos
WHERE tipo = 'materia_prima' OR id = (SELECT insumo_id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo) ORDER BY tipo, codigo;

-- ---------------------------------------------------------------------
-- 16. [INSERT] Pedido #2: se cancela antes de cocina
-- Un pedido cancelado en espera no consume inventario ni genera venta.
-- ---------------------------------------------------------------------
INSERT INTO pedidos (tipo, total) VALUES ('mostrador', 8000) RETURNING numero;
INSERT INTO pedido_items (pedido_id, plato_id, nombre, precio_unit, cantidad)
VALUES ((SELECT id FROM pedidos WHERE numero = 2), (SELECT id FROM platos WHERE nombre = 'Pincho solo carne' AND activo), 'Pincho solo carne', 8000, 1);

UPDATE pedidos SET estado = 'cancelado', cancelado_motivo = 'El cliente se fue'
WHERE numero = 2 AND estado = 'espera' RETURNING numero, estado, pagado, factura_id;

SELECT count(*) AS movimientos_del_pedido_2 FROM movimientos_inventario WHERE pedido_id = (SELECT id FROM pedidos WHERE numero = 2);

-- ---------------------------------------------------------------------
-- 17. [INSERT] Pedidos #3 y #4: misma mesa, se cobran juntos
-- El #4 es un complemento («algo más») del #3. Una sola venta agrupa los dos pedidos.
-- ---------------------------------------------------------------------
INSERT INTO pedidos (tipo, mesa, total) VALUES ('mesa', '2', 8000);
INSERT INTO pedido_items (pedido_id, plato_id, nombre, precio_unit, cantidad, sin)
VALUES ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM platos WHERE nombre = 'Pincho de carne con chunchullo' AND activo), 'Pincho de carne con chunchullo', 8000, 1, '{Cebolla}');

INSERT INTO pedidos (tipo, mesa, total, complemento_de) VALUES ('mesa', '2', 5000, (SELECT id FROM pedidos WHERE numero = 3));
INSERT INTO pedido_items (pedido_id, plato_id, nombre, precio_unit, cantidad)
VALUES ((SELECT id FROM pedidos WHERE numero = 4), (SELECT id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo), 'Club Colombia botella 330 ml', 5000, 1);

SELECT numero, mesa, total, (SELECT numero FROM pedidos o WHERE o.id = p.complemento_de) AS complemento_de
FROM pedidos p WHERE numero IN (3, 4) ORDER BY numero;

-- ---------------------------------------------------------------------
-- 18. [UPDATE] Cocina de los pedidos #3 y #4
-- El #3 va SIN cebolla, así que no la descuenta. Chunchullo con 15 % de merma: 60 g ÷ 0,85 = 70,59 g. El #4 solo trae la cerveza.
-- ---------------------------------------------------------------------
WITH items AS (
       SELECT coalesce(cb.plato_id, it.plato_id) AS plato_id, it.cantidad * coalesce(cb.cantidad, 1) AS qty, it.sin
       FROM pedido_items it LEFT JOIN plato_combo cb ON cb.promo_id = it.plato_id
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 3)),
     base AS (                                   -- receta del plato
       SELECT r.insumo_id, r.cantidad * i.qty AS q
       FROM items i JOIN recetas r ON r.plato_id = i.plato_id JOIN insumos s ON s.id = r.insumo_id
       WHERE NOT (s.nombre = ANY (i.sin))),
     opc AS (                                    -- insumos de las opciones elegidas (adicionales)
       SELECT r.insumo_id, r.cantidad * it.cantidad AS q
       FROM pedido_items it CROSS JOIN LATERAL jsonb_array_elements(it.opciones) o
       JOIN opcion_receta r ON r.opcion_id = (o->>'id')::int
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 3)),
     consumo AS (                                -- total por insumo, con la merma
       SELECT x.insumo_id, round(sum(x.q) / (1 - s.merma_pct / 100.0), 2) AS qty, s.cantidad AS stock
       FROM (SELECT * FROM base UNION ALL SELECT * FROM opc) x JOIN insumos s ON s.id = x.insumo_id
       GROUP BY x.insumo_id, s.merma_pct, s.cantidad),
     mov AS (
       INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, delta, motivo, pedido_id, usuario_id)
       SELECT insumo_id, 'salida', qty, -LEAST(stock, qty), 'Pedido en preparación', (SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM usuarios WHERE usuario = 'cocina1')
       FROM consumo RETURNING insumo_id, cantidad)
UPDATE insumos s SET cantidad = GREATEST(s.cantidad - m.cantidad, 0)
FROM mov m WHERE s.id = m.insumo_id;

UPDATE pedidos SET estado = 'preparacion', preparacion_en = now(), inventario_descontado = TRUE
WHERE numero = 3 AND NOT inventario_descontado;

WITH items AS (
       SELECT coalesce(cb.plato_id, it.plato_id) AS plato_id, it.cantidad * coalesce(cb.cantidad, 1) AS qty, it.sin
       FROM pedido_items it LEFT JOIN plato_combo cb ON cb.promo_id = it.plato_id
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 4)),
     base AS (                                   -- receta del plato
       SELECT r.insumo_id, r.cantidad * i.qty AS q
       FROM items i JOIN recetas r ON r.plato_id = i.plato_id JOIN insumos s ON s.id = r.insumo_id
       WHERE NOT (s.nombre = ANY (i.sin))),
     opc AS (                                    -- insumos de las opciones elegidas (adicionales)
       SELECT r.insumo_id, r.cantidad * it.cantidad AS q
       FROM pedido_items it CROSS JOIN LATERAL jsonb_array_elements(it.opciones) o
       JOIN opcion_receta r ON r.opcion_id = (o->>'id')::int
       WHERE it.pedido_id = (SELECT id FROM pedidos WHERE numero = 4)),
     consumo AS (                                -- total por insumo, con la merma
       SELECT x.insumo_id, round(sum(x.q) / (1 - s.merma_pct / 100.0), 2) AS qty, s.cantidad AS stock
       FROM (SELECT * FROM base UNION ALL SELECT * FROM opc) x JOIN insumos s ON s.id = x.insumo_id
       GROUP BY x.insumo_id, s.merma_pct, s.cantidad),
     mov AS (
       INSERT INTO movimientos_inventario (insumo_id, tipo, cantidad, delta, motivo, pedido_id, usuario_id)
       SELECT insumo_id, 'salida', qty, -LEAST(stock, qty), 'Pedido en preparación', (SELECT id FROM pedidos WHERE numero = 4), (SELECT id FROM usuarios WHERE usuario = 'cocina1')
       FROM consumo RETURNING insumo_id, cantidad)
UPDATE insumos s SET cantidad = GREATEST(s.cantidad - m.cantidad, 0)
FROM mov m WHERE s.id = m.insumo_id;

UPDATE pedidos SET estado = 'preparacion', preparacion_en = now(), inventario_descontado = TRUE
WHERE numero = 4 AND NOT inventario_descontado;

-- «Antes» = existencia actual + lo que salió por estos pedidos
SELECT s.nombre AS insumo, s.unidad,
       s.cantidad - coalesce(sum(m.delta), 0) AS antes,
       coalesce(-sum(m.delta), 0)             AS salio,
       s.cantidad                             AS despues
FROM insumos s LEFT JOIN movimientos_inventario m ON m.insumo_id = s.id AND m.pedido_id IN ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM pedidos WHERE numero = 4))
WHERE s.tipo = 'materia_prima' OR s.id = (SELECT insumo_id FROM platos WHERE nombre = 'Club Colombia botella 330 ml' AND activo)
GROUP BY s.id ORDER BY s.tipo, s.codigo;

-- ---------------------------------------------------------------------
-- 19. [UPDATE] Cobro conjunto de #3 y #4 en UNA factura
-- Factura 1 ── 2 pedidos.
-- ---------------------------------------------------------------------
UPDATE pedidos SET estado = 'entregado' WHERE numero IN (3, 4);

BEGIN;
-- 1) Bloquear los pedidos: si otro cajero intenta cobrarlos al tiempo, espera aquí
SELECT numero, total, pagado, estado FROM pedidos WHERE id IN ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM pedidos WHERE numero = 4)) ORDER BY numero FOR UPDATE;

-- 2) Crear la venta (factura) con el siguiente número consecutivo y la copia de lo cobrado
INSERT INTO facturas (numero, turno_id, cajero_id, cajero, pedido_ids, numeros_pedido, tipo, mesa,
                      items, total, metodo_pago, recibido, vueltos)
SELECT (SELECT coalesce(max(numero), 0) + 1 FROM facturas), (SELECT id FROM turnos_caja WHERE cerrado_en IS NULL), (SELECT id FROM usuarios WHERE usuario = 'caja1'), 'caja1',
       array_agg(p.id ORDER BY p.numero), array_agg(p.numero ORDER BY p.numero), min(p.tipo), min(p.mesa),
       (SELECT jsonb_agg(jsonb_build_object('nombre', it.nombre, 'cantidad', it.cantidad, 'precio_unit', it.precio_unit, 'sin', it.sin) ORDER BY it.id)
          FROM pedido_items it WHERE it.pedido_id IN ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM pedidos WHERE numero = 4))),
       sum(p.total), 'efectivo', 20000, 20000 - sum(p.total)
FROM pedidos p WHERE p.id IN ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM pedidos WHERE numero = 4)) AND NOT p.pagado AND p.estado <> 'cancelado'
RETURNING numero AS factura, numeros_pedido AS pedidos, total, recibido, vueltos;

-- 3) Marcar los pedidos como pagados y ligarlos a su venta (pedidos.factura_id → facturas.id)
UPDATE pedidos SET pagado = TRUE, pagado_en = now(), turno_id = (SELECT id FROM turnos_caja WHERE cerrado_en IS NULL), metodo_pago = 'efectivo',
       factura_id = (SELECT max(id) FROM facturas)
WHERE id IN ((SELECT id FROM pedidos WHERE numero = 3), (SELECT id FROM pedidos WHERE numero = 4)) AND NOT pagado
RETURNING numero, pagado, factura_id;
COMMIT;

-- ---------------------------------------------------------------------
-- 20. [DELETE] Quitar un insumo de una receta
-- La cebolla ya no va en el pincho solo carne.
-- ---------------------------------------------------------------------
DELETE FROM recetas
WHERE plato_id = (SELECT id FROM platos WHERE nombre = 'Pincho solo carne' AND activo) AND insumo_id = (SELECT id FROM insumos WHERE codigo = 'CEB')
RETURNING plato_id, insumo_id, cantidad;

-- ---------------------------------------------------------------------
-- 21. [DELETE] Borrar un anuncio vencido
-- Los anuncios sí se pueden borrar: nada depende de ellos.
-- ---------------------------------------------------------------------
DELETE FROM anuncios WHERE titulo = 'Martes de pinchos' RETURNING id, titulo;

-- ---------------------------------------------------------------------
-- 22. [DELETE] Borrar una presentación de compra
-- Presentación que ya no se usa.
-- ---------------------------------------------------------------------
DELETE FROM presentaciones WHERE nombre = 'Bulto 25 kg' RETURNING id, nombre;

-- ---------------------------------------------------------------------
-- 23. [UPDATE] Borrado lógico de un plato
-- Un plato con ventas no se borra físicamente (lo impide la clave foránea de pedido_items): se desactiva y desaparece de la carta, pero el historial queda.
-- ---------------------------------------------------------------------
UPDATE platos SET activo = FALSE WHERE nombre = 'Pincho de rellena' RETURNING id, nombre, activo;

-- ---------------------------------------------------------------------
-- 24. [REGLAS] Intentos que la base de datos rechaza
-- Cada intento va dentro de un bloque que captura el error para mostrarlo.
-- ---------------------------------------------------------------------
-- a) Cambiar la venta de un pedido ya cobrado (pedido #1 a la factura 2)
DO $$ BEGIN
  UPDATE pedidos SET factura_id = (SELECT id FROM facturas WHERE numero = 2) WHERE numero = 1;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- b) Asignar una venta a un pedido cancelado y sin pagar (#2)
DO $$ BEGIN
  UPDATE pedidos SET factura_id = (SELECT id FROM facturas WHERE numero = 1) WHERE numero = 2;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- c) Borrar o modificar una factura
DO $$ BEGIN
  DELETE FROM facturas WHERE numero = 1;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

DO $$ BEGIN
  UPDATE facturas SET total = 1000 WHERE numero = 1;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- d) Borrar físicamente un plato que ya se vendió
DO $$ BEGIN
  DELETE FROM platos WHERE nombre = 'Pincho mixto';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- e) Existencia negativa
DO $$ BEGIN
  UPDATE insumos SET cantidad = -5 WHERE codigo = 'CAR';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- f) Abrir un segundo turno de caja
DO $$ BEGIN
  INSERT INTO turnos_caja (abierto_por, monto_apertura) VALUES ((SELECT id FROM usuarios WHERE usuario = 'caja1'), 50000);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RECHAZADO: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- 25. [SELECT] Cuántas ventas tiene cada pedido (cardinalidad 0..1)
-- Cada pedido tiene como máximo una venta: el cancelado no tiene ninguna.
-- ---------------------------------------------------------------------
SELECT p.numero AS pedido, p.estado, p.pagado, f.numero AS factura
FROM pedidos p LEFT JOIN facturas f ON f.id = p.factura_id ORDER BY p.numero;

-- ---------------------------------------------------------------------
-- 26. [SELECT] Cuántos pedidos agrupa cada venta (1..*)
-- Una venta agrupa uno o varios pedidos.
-- ---------------------------------------------------------------------
SELECT f.numero AS factura, count(p.id) AS pedidos, string_agg('#' || p.numero, ', ' ORDER BY p.numero) AS cuales, f.total
FROM facturas f JOIN pedidos p ON p.factura_id = f.id GROUP BY f.id ORDER BY f.numero;

-- ---------------------------------------------------------------------
-- 27. [SELECT] Productos más vendidos
-- Solo pedidos pagados.
-- ---------------------------------------------------------------------
SELECT it.nombre, sum(it.cantidad) AS unidades, sum(it.cantidad * it.precio_unit) AS vendido
FROM pedido_items it JOIN pedidos p ON p.id = it.pedido_id
WHERE p.pagado GROUP BY it.nombre ORDER BY vendido DESC;

-- ---------------------------------------------------------------------
-- 28. [SELECT] Ventas del turno abierto
-- Lo que el administrador ve al cerrar la caja.
-- ---------------------------------------------------------------------
SELECT count(*) AS ventas, sum(total) AS total_vendido, sum(recibido) AS efectivo_recibido, sum(vueltos) AS vueltos
FROM facturas WHERE turno_id = (SELECT id FROM turnos_caja WHERE cerrado_en IS NULL);

-- ---------------------------------------------------------------------
-- 29. [SELECT] Costo de lo vendido y utilidad bruta por pedido
-- Costo = salidas de inventario × costo unitario del insumo.
-- ---------------------------------------------------------------------
SELECT p.numero AS pedido, p.total AS venta,
       round(coalesce(sum(-m.delta * s.costo_unitario), 0)) AS costo_insumos,
       p.total - round(coalesce(sum(-m.delta * s.costo_unitario), 0)) AS utilidad_bruta
FROM pedidos p LEFT JOIN movimientos_inventario m ON m.pedido_id = p.id
LEFT JOIN insumos s ON s.id = m.insumo_id
WHERE p.pagado GROUP BY p.id ORDER BY p.numero;

-- ---------------------------------------------------------------------
-- 30. [SELECT] Historial de movimientos de un insumo (kárdex de la carne)
-- Toda entrada y salida queda registrada con su origen.
-- ---------------------------------------------------------------------
SELECT m.creado_en::time(0) AS hora, m.tipo, m.delta, m.motivo, p.numero AS pedido
FROM movimientos_inventario m JOIN insumos s ON s.id = m.insumo_id LEFT JOIN pedidos p ON p.id = m.pedido_id
WHERE s.codigo = 'CAR' ORDER BY m.id;

-- ---------------------------------------------------------------------
-- 31. [UPDATE] Mínimos y máximos de las materias primas
-- Topes para el manejo de los pedidos: al llegar al mínimo hay que pedir hasta el máximo. Un CHECK impide un máximo menor que el mínimo.
-- ---------------------------------------------------------------------
UPDATE insumos SET stock_min = v.minimo, stock_max = v.maximo
FROM (VALUES ('CAR', 9900, 20000), ('POL', 4000, 15000), ('CHU', 1000, 4000), ('CEB', 2000, 6000), ('ARR', 4800, 25000))
     AS v(codigo, minimo, maximo)
WHERE insumos.codigo = v.codigo
RETURNING insumos.codigo, insumos.nombre, insumos.cantidad, insumos.stock_min, insumos.stock_max;

-- ---------------------------------------------------------------------
-- 32. [SELECT] Pedido a proveedores
-- Lo que está en su mínimo o por debajo, y cuánto pedir para llegar al máximo, con su costo estimado. Es la misma consulta de Inventario → Pedido a proveedores.
-- ---------------------------------------------------------------------
SELECT i.tipo, i.nombre, i.cantidad AS hay, i.stock_min AS minimo, i.stock_max AS maximo,
       greatest(coalesce(i.stock_max, i.stock_min * 2) - i.cantidad, 0) AS pedir, i.unidad,
       round(greatest(coalesce(i.stock_max, i.stock_min * 2) - i.cantidad, 0) * i.costo_unitario) AS costo_estimado
FROM insumos i
WHERE i.activo AND i.stock_min IS NOT NULL AND i.cantidad <= i.stock_min
ORDER BY i.tipo, i.nombre;

-- ---------------------------------------------------------------------
-- 33. [SELECT] Platos y productos de tienda: costo y ganancia
-- Un plato se costea con su receta; un producto de tienda con su costo de compra (columna costo_fijo).
-- ---------------------------------------------------------------------
SELECT p.tipo, p.nombre, p.precio,
       CASE WHEN p.tipo = 'producto' THEN p.costo_fijo
            ELSE round(sum(r.cantidad / (1 - i.merma_pct / 100.0) * i.costo_unitario)) END AS costo,
       p.precio - CASE WHEN p.tipo = 'producto' THEN p.costo_fijo
            ELSE round(sum(r.cantidad / (1 - i.merma_pct / 100.0) * i.costo_unitario)) END AS ganancia
FROM platos p LEFT JOIN recetas r ON r.plato_id = p.id LEFT JOIN insumos i ON i.id = r.insumo_id
WHERE p.nombre IN ('Pincho mixto', 'Pincho solo carne', 'Pincho de carne con chunchullo', 'Club Colombia botella 330 ml')
GROUP BY p.id ORDER BY p.tipo, p.nombre;

