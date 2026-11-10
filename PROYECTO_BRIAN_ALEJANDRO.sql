-- Databricks notebook source
-- PROYECTO_BRIAN_ALEJANDRO
-- Las cifras de las conclusiones fueron calculadas a partir de los seis CSV entregados.
-- Las tablas deben existir en el catalogo y esquema indicados.
USE CATALOG cursodataacademy;

-- COMMAND ----------
USE SCHEMA curso_sql;

-- COMMAND ----------
-- PREGUNTA 1. INNER JOIN: ¿Como se distribuyen los diagnosticos vinculados a pacientes por tipo de visita?
WITH diagnosticos_vinculados AS (
    SELECT d.patient_id, d.visit_type
    FROM patients AS p
    INNER JOIN diagnoses AS d
        ON p.patient_id = d.patient_id
)
SELECT visit_type, COUNT(*) AS diagnosticos,
       COUNT(DISTINCT patient_id) AS pacientes_distintos
FROM diagnosticos_vinculados
GROUP BY visit_type
UNION ALL
SELECT 'TOTAL', COUNT(*), COUNT(DISTINCT patient_id)
FROM diagnosticos_vinculados;
-- CONCLUSION DE NEGOCIO: Los 274.592 diagnosticos se vinculan a 100.000 pacientes.
-- Las visitas outpatient concentran 164.581 registros (59,94 %); son registros, no personas unicas.

-- COMMAND ----------
-- PREGUNTA 2. LEFT JOIN: ¿Cuantos pacientes tienen registros de medicamentos y cuantos no?
WITH medicamentos_por_paciente AS (
    SELECT patient_id, COUNT(*) AS registros_medicamentos
    FROM medications
    GROUP BY patient_id
), base AS (
    SELECT p.patient_id, COALESCE(m.registros_medicamentos, 0) AS registros_medicamentos
    FROM patients AS p
    LEFT JOIN medicamentos_por_paciente AS m
        ON p.patient_id = m.patient_id
)
SELECT CASE WHEN registros_medicamentos = 0 THEN 'Sin registros de medicamentos'
            ELSE 'Con registros de medicamentos' END AS grupo,
       COUNT(*) AS pacientes
FROM base
GROUP BY CASE WHEN registros_medicamentos = 0 THEN 'Sin registros de medicamentos'
              ELSE 'Con registros de medicamentos' END;
-- CONCLUSION DE NEGOCIO: 94.067 pacientes tienen registros de medicamentos y 5.933 no.
-- La cobertura registrada es 94,07 % de la base; no tener una fila no prueba ausencia de tratamiento.

-- COMMAND ----------
-- PREGUNTA 3. RIGHT OUTER JOIN: ¿Que parte de la base cuenta con un outcome registrado?
SELECT CASE WHEN o.patient_id IS NULL THEN 'Sin outcome registrado'
            ELSE 'Con outcome registrado' END AS grupo,
       COUNT(*) AS pacientes
FROM outcomes AS o
RIGHT OUTER JOIN patients AS p
    ON o.patient_id = p.patient_id
GROUP BY CASE WHEN o.patient_id IS NULL THEN 'Sin outcome registrado'
              ELSE 'Con outcome registrado' END;
-- CONCLUSION DE NEGOCIO: 11.001 pacientes tienen un outcome en este archivo y 88.999 no.
-- Esta cobertura describe los registros disponibles, no la historia hospitalaria completa.

-- COMMAND ----------
-- PREGUNTA 4. FULL OUTER JOIN: ¿Como se superponen medicamentos y outcomes?
WITH medicamentos_por_paciente AS (
    SELECT patient_id, COUNT(*) AS registros_medicamentos
    FROM medications
    GROUP BY patient_id
), cobertura AS (
    SELECT COALESCE(m.patient_id, o.patient_id) AS patient_id,
           CASE WHEN m.patient_id IS NOT NULL AND o.patient_id IS NOT NULL
                    THEN 'Ambas fuentes'
                WHEN m.patient_id IS NOT NULL THEN 'Solo medicamentos'
                ELSE 'Solo outcomes' END AS presencia
    FROM medicamentos_por_paciente AS m
    FULL OUTER JOIN outcomes AS o
        ON m.patient_id = o.patient_id
)
SELECT presencia, COUNT(*) AS pacientes
FROM cobertura
GROUP BY presencia;
-- CONCLUSION DE NEGOCIO: 10.732 pacientes figuran en ambas fuentes; 83.335 solo en
-- medicamentos y 269 solo en outcomes. Hay 5.664 pacientes fuera de ambas fuentes.

-- COMMAND ----------
-- PREGUNTA 5. CROSS JOIN: ¿Los pesos Charlson reproducen el indice registrado por paciente?
WITH matriz AS (
    SELECT p.patient_id, p.charlson_index, c.condition_name, c.cci_weight,
           CASE c.condition_name
               WHEN 'Coronary artery disease' THEN CAST(p.dx_coronary_artery_disease AS INT)
               WHEN 'Heart failure' THEN CAST(p.dx_heart_failure AS INT)
               WHEN 'COPD' THEN CAST(p.dx_copd AS INT)
               WHEN 'Type 2 diabetes' THEN CAST(p.dx_type2_diabetes AS INT)
               WHEN 'Chronic kidney disease' THEN CAST(p.dx_chronic_kidney_disease AS INT)
               WHEN 'Type 1 diabetes' THEN CAST(p.dx_type1_diabetes AS INT)
               ELSE 0
           END AS tiene_condicion
    FROM patients AS p
    CROSS JOIN charlson_comorbidity_index AS c
), puntaje AS (
    SELECT patient_id, MAX(CAST(charlson_index AS INT)) AS indice_registrado,
           SUM(tiene_condicion * CAST(cci_weight AS INT)) AS indice_calculado
    FROM matriz
    GROUP BY patient_id
)
SELECT COUNT(*) AS pacientes_evaluados,
       SUM(CASE WHEN indice_registrado = indice_calculado THEN 1 ELSE 0 END)
           AS indices_coincidentes,
       SUM(CASE WHEN indice_registrado <> indice_calculado THEN 1 ELSE 0 END)
           AS indices_diferentes
FROM puntaje;
-- CONCLUSION DE NEGOCIO: El indice calculado coincide para los 100.000 pacientes;
-- se detectaron 0 diferencias entre los pesos de la dimension y el dato registrado.

-- COMMAND ----------
-- PREGUNTA 6. INTEGRACION: ¿Se pueden relacionar las seis tablas sin duplicar pacientes?
CREATE OR REPLACE TEMP VIEW proyecto_final_pacientes AS
WITH diagnosticos AS (
    SELECT patient_id, COUNT(*) AS cantidad_diagnosticos
    FROM diagnoses
    GROUP BY patient_id
), laboratorios AS (
    SELECT patient_id, COUNT(*) AS cantidad_pruebas,
           SUM(CASE WHEN CAST(is_abnormal AS INT) = 1 THEN 1 ELSE 0 END)
               AS pruebas_anormales
    FROM lab_results
    GROUP BY patient_id
), medicamentos AS (
    SELECT patient_id, COUNT(*) AS cantidad_medicamentos
    FROM medications
    GROUP BY patient_id
), charlson AS (
    SELECT p.patient_id,
           SUM(CAST(c.cci_weight AS INT) *
               CASE c.condition_name
                   WHEN 'Coronary artery disease' THEN CAST(p.dx_coronary_artery_disease AS INT)
                   WHEN 'Heart failure' THEN CAST(p.dx_heart_failure AS INT)
                   WHEN 'COPD' THEN CAST(p.dx_copd AS INT)
                   WHEN 'Type 2 diabetes' THEN CAST(p.dx_type2_diabetes AS INT)
                   WHEN 'Chronic kidney disease' THEN CAST(p.dx_chronic_kidney_disease AS INT)
                   WHEN 'Type 1 diabetes' THEN CAST(p.dx_type1_diabetes AS INT)
                   ELSE 0
               END) AS indice_charlson_calculado
    FROM patients AS p
    CROSS JOIN charlson_comorbidity_index AS c
    GROUP BY p.patient_id
)
SELECT p.patient_id, p.age, p.sex, CAST(p.charlson_index AS INT) AS charlson_index,
       COALESCE(d.cantidad_diagnosticos, 0) AS cantidad_diagnosticos,
       COALESCE(l.cantidad_pruebas, 0) AS cantidad_pruebas,
       COALESCE(l.pruebas_anormales, 0) AS pruebas_anormales,
       COALESCE(m.cantidad_medicamentos, 0) AS cantidad_medicamentos,
       CASE WHEN o.patient_id IS NULL THEN 0 ELSE 1 END AS tiene_outcome,
       o.admission_date, o.length_of_stay_days,
       CAST(o.readmitted_30d AS INT) AS readmitted_30d,
       c.indice_charlson_calculado
FROM patients AS p
LEFT JOIN diagnosticos AS d ON p.patient_id = d.patient_id
LEFT JOIN laboratorios AS l ON p.patient_id = l.patient_id
LEFT JOIN medicamentos AS m ON p.patient_id = m.patient_id
LEFT JOIN outcomes AS o ON p.patient_id = o.patient_id
LEFT JOIN charlson AS c ON p.patient_id = c.patient_id;

-- COMMAND ----------
SELECT COUNT(*) AS filas,
       COUNT(DISTINCT patient_id) AS pacientes_distintos,
       SUM(CASE WHEN charlson_index <> indice_charlson_calculado THEN 1 ELSE 0 END)
           AS diferencias_charlson,
       SUM(CASE WHEN cantidad_medicamentos = 0 THEN 1 ELSE 0 END)
           AS pacientes_sin_medicamentos,
       SUM(CASE WHEN tiene_outcome = 0 THEN 1 ELSE 0 END)
           AS pacientes_sin_outcome
FROM proyecto_final_pacientes;
-- CONCLUSION DE NEGOCIO: La vista integra las seis fuentes en 100.000 filas y
-- 100.000 pacientes distintos, sin duplicacion ni diferencias en el indice Charlson.
