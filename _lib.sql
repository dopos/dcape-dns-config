/*
  Вспомогательные функции

* FUNCTION soa_upd(a_old TEXT) RETURNS TEXT
* FUNCTION domain_id(a_name TEXT, a_type TEXT DEFAULT 'NATIVE') RETURNS INTEGER
* PROCEDURE acme_insert(a_domain_id INT, a_name TEXT, a_ip TEXT, a_ttl INT)

*/

CREATE OR REPLACE FUNCTION soa_upd(a_old TEXT) RETURNS TEXT AS $_$
/*
    принять SOA, проверить на "сегодня", если сегодня, то во вторую пару цифр сделать +1
    если не сегодня, или null, то сегодня += 00
    если SOA в принципе не по дате, к ней сделать +1
*/
DECLARE
  v_soa TEXT;
  v_id  INTEGER;
BEGIN
  v_soa := to_char(current_timestamp, 'YYYYMMDD');
  IF a_old IS NULL OR a_old < v_soa || '00' THEN
    -- SOA нет или меньше сегодняшнего
    RETURN v_soa || '00';
  END IF;
  v_id := substr(a_old, length(v_soa) + 1)::INT + 1;
  v_soa := substr(a_old, 1, length(v_soa)) || CASE WHEN v_id < 10 THEN '0' ELSE  '' END || v_id::TEXT;
  RETURN v_soa;
END
$_$ LANGUAGE plpgsql;

/*
SELECT x, soa_upd(x) FROM unnest(ARRAY[
  null
, '2023060100'
, '2023060600'
, '2023060604'
, '2023060624'
, '2024060624'
, '202406061100'
]) x;
*/

CREATE OR REPLACE FUNCTION domain_id(a_name TEXT, a_type TEXT DEFAULT 'NATIVE') RETURNS INTEGER AS $_$
/*
  Вернуть ID домена, создав его при необходимости
*/
DECLARE
  v_id  INTEGER;
BEGIN
  SELECT INTO v_id id FROM domains WHERE name = a_name;
  IF NOT FOUND THEN
    INSERT INTO domains (name, type) VALUES
      (a_name, a_type)
      RETURNING id INTO v_id
    ;
  END IF;
  RETURN v_id;
END
$_$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE acme_insert(a_domain_id INT, a_name TEXT, a_ip TEXT, a_ttl INT) AS $_$
/*
  Добавление в зону для заданного a_ip записей для передачи ему контроля над зоной a_name.
  Это используется в DNS-01 challenge ACME
*/
BEGIN
  WITH acme(name, type, content) AS (VALUES
    (                      a_name, 'A',     a_ip)
  , ('*.'               || a_name, 'A',     a_ip)
  , ('acme-'            || a_name, 'NS',    'ns.'   || a_name)
  , ('_acme-challenge.' || a_name, 'CNAME', 'acme-' || a_name)
  )
  INSERT INTO records (domain_id, name, ttl, type, prio, content)
    SELECT a_domain_id, name, a_ttl, type, 0, content
      FROM acme
  ;
END;
$_$ LANGUAGE plpgsql;
