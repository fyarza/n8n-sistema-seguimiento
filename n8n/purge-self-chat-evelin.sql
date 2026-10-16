-- One-off. Chat de Evelin consigo misma (lead 5, 584244733047).
-- whatsapp_messages y lead_score_events caen por ON DELETE CASCADE.
-- No toca otros leads. No corre solo: ejecutalo en Postgres.
-- Guard: solo borra si ese telefono no tiene ningun mensaje de cliente.

BEGIN;

SELECT l.id, l.phone, l.display_name, l.stage, l.score_cierre,
       COUNT(m.id) AS messages,
       COUNT(m.id) FILTER (WHERE NOT m.from_me) AS client_messages,
       (SELECT COUNT(*) FROM lead_score_events e WHERE e.lead_id = l.id) AS score_events
FROM leads l
LEFT JOIN whatsapp_messages m ON m.lead_id = l.id
WHERE l.phone = '584244733047'
GROUP BY l.id;

DELETE FROM leads l
WHERE l.phone = '584244733047'
  AND NOT EXISTS (
    SELECT 1
    FROM whatsapp_messages m
    WHERE m.lead_id = l.id
      AND NOT m.from_me
  );

COMMIT;
