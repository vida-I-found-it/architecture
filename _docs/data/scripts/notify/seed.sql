-- =====================================================================
-- NOTIFY · semillas (EJ-3, DEC-33)
-- Se corre DESPUÉS de schema.sql, con el rol `NOTIFY_SERVICE`. Idempotente:
-- correrla de nuevo no duplica nada. El canal `email` ya lo siembra
-- schema.sql. El texto definitivo de las plantillas se afina en la
-- historia de CU-10; aquí va un cuerpo mínimo y válido (Jinja2).
-- Cambiar una plantilla = INSERT de una VERSION nueva, nunca UPDATE del BODY.
-- =====================================================================
SET search_path TO NOTIFY;

INSERT INTO TEMPLATE (CODE, VERSION, CHANNEL_ID, SYSTEM, SUBJECT, BODY) VALUES
    ('price-drop-email', 1, 'email', 'ifoundit',
     'Bajó el precio de {{ alert_title }}',
     '<p>El mejor precio de <strong>{{ alert_title }}</strong> bajó a {{ best_price_cop }} COP en {{ best_site }}.</p>'
     '<p>Precio anterior: {{ previous_price_cop }} COP.</p>'
     '{% if is_anomalous %}<p>Ojo: es una caída inusual, revisa el sitio antes de comprar.</p>{% endif %}'
     '<p><a href="{{ product_url }}">Ver el producto</a></p>'
     '<p><a href="{{ unsubscribe_url }}">Dejar de recibir avisos de esta alerta</a></p>'),
    -- Barrido diario (DEC-26, DEC-32): solo identificadores y códigos de error, sin PII.
    ('admin-alert-email', 1, 'email', 'ifoundit',
     'I Found It: {{ failed_count }} fallos desde {{ since }}',
     '<p>Fallos desde {{ since }}, agrupados por job:</p><ul>'
     '{% for job in jobs %}<li>Job {{ job.job_id }}: '
     '{% for f in job.failures %}{{ f.transaction_id }} ({{ f.error_code }}){% if not loop.last %}, {% endif %}{% endfor %}'
     '</li>{% endfor %}</ul>')
ON CONFLICT (CODE, VERSION) DO NOTHING;
