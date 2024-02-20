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

-- result was changed to bigint
-- DROP FUNCTION IF EXISTS domain_id(text,text);

CREATE OR REPLACE FUNCTION domain_id(a_name TEXT, a_type TEXT DEFAULT 'NATIVE') RETURNS BIGINT AS $_$
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

CREATE OR REPLACE PROCEDURE acme_insert(a_domain_id BIGINT, a_name TEXT, a_ip TEXT, a_ttl INT) AS $_$
/*
  Добавление в зону для заданного a_ip записей для передачи ему контроля над зоной a_name.
  Это используется в DNS-01 challenge ACME
*/
BEGIN
  WITH acme(name, type, content) AS (VALUES
    (                      a_name, 'A',     a_ip)               -- зону резолвим в a_ip
  , ('*.'               || a_name, 'A',     a_ip)               -- wildcard зоны резолвим в a_ip
  , ('acme-'            || a_name, 'NS',    'ns.'   || a_name)  -- создаем специальную зону для DNS-01, её резолвит NS сервер, доступный по a_ip
  , ('_acme-challenge.' || a_name, 'CNAME', 'acme-' || a_name)  -- делегируем DNS-01 зоны a_name в специальную зону
  )
  INSERT INTO records (domain_id, name, ttl, type, prio, content)
    SELECT a_domain_id, name, a_ttl, type, 0, content
      FROM acme
  ;
END;
$_$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION soa_mk(
  a_domain_id BIGINT
, a_ns_admin TEXT
, a_refresh  INTEGER DEFAULT  10800 -- 3 hours
, a_retry    INTEGER DEFAULT   3600 -- 1 hour
, a_expire   INTEGER DEFAULT 604800 -- 7 days
, a_ttl      INTEGER DEFAULT   1800 -- 30 min
) RETURNS TEXT AS $_$
/*
  Получить новый серийный номер зоны, проверить наличие NSERVER и вернуть строку SOA

  refresh -- time lag until the slave again asks the master for a current version of the zone file
  retry   -- Should this request go unanswered, the “Retry” field regulates when a new attempt is to be carried out (< refresh)
  expire  -- determines how long the zone file may still be used before the server refuses DNS information delivery
  ttl     -- how long a client may hold the requested information in the cache before a new request must be sent

  Each value in seconds
*/
DECLARE
  v_ns        text := current_setting('vars.ns');   -- master DNS host
  v_stamp     text;                       -- zone SOA timestamp
  v_stamp_old text;                       -- previous zone SOA timestamp
BEGIN
  -- check NSERVER
  IF coalesce(v_ns,'') = '' THEN
    RAISE EXCEPTION 'NSERVER is not set';
  END IF;
  -- calculate SOA with next serial
  SELECT INTO v_stamp_old split_part(content, ' ', 3) FROM records WHERE domain_id = a_domain_id AND type = 'SOA';
  v_stamp := soa_upd(v_stamp_old);

  RETURN concat_ws(' ', v_ns, a_ns_admin, v_stamp, a_refresh, a_retry, a_expire, a_ttl);
END;
$_$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION csum_exists(a_domain_id BIGINT) RETURNS BOOL AS $_$
/*
  Проверить совпадение vars.csum с загруженным в БД прошлый раз.
  Если нет таблицы dcape_csum - создать ее
  Если csum отличается - обновить
*/
DECLARE
  v_csum     text := current_setting('vars.csum');   -- file csum
  v_csum_old text;
BEGIN
  RAISE NOTICE 'Source csum: %', v_csum;
  IF to_regclass('public.dcape_csum') IS NULL THEN
    CREATE TABLE dcape_csum(
      domain_id bigint primary key REFERENCES domains(id) ON DELETE CASCADE
    , csum text
    , updated_at timestamptz(0)
    );
  ELSE
    SELECT INTO v_csum_old csum FROM dcape_csum WHERE domain_id = a_domain_id;
  END IF;
  IF v_csum_old IS NULL THEN
    INSERT INTO dcape_csum(domain_id, csum, updated_at) VALUES (a_domain_id, v_csum, now());
  ELSIF v_csum_old <> v_csum THEN
    UPDATE dcape_csum SET csum = v_csum, updated_at = now() WHERE domain_id = a_domain_id;
  ELSE
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$_$ LANGUAGE plpgsql;
