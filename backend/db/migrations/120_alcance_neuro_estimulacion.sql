-- =============================================================================
-- 120 · Alcance del sistema de horarios (14/10/2026)
-- El sistema cubre solo las áreas de iSmart: Neuro estimulación y
-- Estimulación temprana. Inglés y e-commerce quedan fuera.
-- Solo se actualizan descripciones; la estructura no cambia.
-- =============================================================================

COMMENT ON TABLE catalogo.areas IS
  'Áreas de negocio: Neuro estimulación y Estimulación temprana. Los coordinadores e informes se separan por área.';

COMMENT ON COLUMN catalogo.programas.cupo_maximo IS
  'Máximo de pacientes por sesión. Paramétrico: cada programa define el suyo (por ejemplo 5 en terapia grupal).';

COMMENT ON COLUMN seguridad.usuario_roles.area_id IS
  'Vacío = todas las áreas. Un coordinador de Neuro estimulación no ve informes de Estimulación temprana.';

COMMENT ON COLUMN matriculas.matriculas.origen IS
  'Por ahora todas las matrículas son PRESENCIAL. El valor ECOMMERCE queda reservado; no hay e-commerce en este sistema.';
