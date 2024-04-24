# app dcape v3 dns-config Makefile.

SHELL         = /bin/sh
CFG           = .env
CFG_BAK            ?= $(CFG).bak

SOURCES      ?= _lib.sql $(wildcard *.sql)
OBJECTS       = $(SOURCES:.sql=.done)
OBJECTSDIRECT = $(SOURCES:.sql=.direct)

# ------------------------------------------------------------------------------
# app custom config
# comments prefixed with '#- ' will be copied to $(CFG).sample

#- ACME zone suffix
ACME_DOMAIN     ?= dev.test

#- This NS hostname for use in all SOA
NSERVER         ?= ns.test

#- db container (autofilled)
DB_CONTAINER    ?= #

#- PowerDNS DB user name
PGUSER          ?= pdns

#- PowerDNS DB name
PGDATABASE      ?= pdns

#- direct DB access without docker (update-direct)
PGPASSWORD      ?= $(shell openssl rand -hex 16; echo)

#- Used for direct DB access without docker (update-direct)
DB_PORT_LOCAL   ?=

USE_DCAPE_DC    := no

# Local DNS config

#- Schema and user name
LOCAL_PGUSER     ?= pdnslocal
#- Password
LOCAL_PGPASSWORD ?= $(shell openssl rand -hex 16; echo)

# script for local-init
LOCAL_INIT_SQL   ?= local_init.psql

# ------------------------------------------------------------------------------
-include $(CFG)
export

# ------------------------------------------------------------------------------

ifneq ($(findstring $(MAKECMDGOALS),psql),)
  USE_DB := yes
else ifneq ($(findstring $(MAKECMDGOALS),psql-local),)
  USE_DB := yes
  ifndef DB_PORT_LOCAL
    $(error "DB_PORT_LOCAL must be set - $(MAKECMDGOALS)")
  endif
endif

# ------------------------------------------------------------------------------
# Find and include DCAPE_ROOT/Makefile
#- dcape compose docker image
DCAPE_COMPOSE   ?= dcape-compose
DCAPE_ROOT      ?= $(shell docker inspect -f "{{.Config.Labels.dcape_root}}" $(DCAPE_COMPOSE))

ifeq ($(shell test -e $(DCAPE_ROOT)/Makefile.app && echo -n yes),yes)
  include $(DCAPE_ROOT)/Makefile.app
else
  include /opt/dcape/Makefile.app
endif

# ------------------------------------------------------------------------------
## DB operations
#:
.PHONY: update

update: $(OBJECTS)

%.done: %.sql
	@echo "*** $< ***"
	@csum=$$(md5sum $< | sed 's/ .*//') ; \
	  cat $< | docker exec -i $$DB_CONTAINER psql -U $$PGUSER -d $$PGDATABASE \
	     -vcsum=$$csum -vACME_DOMAIN=$(ACME_DOMAIN) -vNSERVER=$(NSERVER) -vLOCAL_PGUSER=$$LOCAL_PGUSER > $@

## Load updated zone files via psql connection
update-direct: $(CFG) $(OBJECTSDIRECT)

%.direct: %.sql
	@echo "*** $< ***"
	@source $(CFG) && cat $< | PGPASSWORD=$${PGPASSWORD:?Must be set} psql -h localhost -U $$PGUSER -p $${DB_PORT_LOCAL:?Must be set} > $@

# ------------------------------------------------------------------------------

local-init:
	@echo "Create user $$LOCAL_PGUSER for db $$PGDATABASE via $$DB_CONTAINER..." ; \
	sql="CREATE USER \"$$LOCAL_PGUSER\" WITH PASSWORD '$$LOCAL_PGPASSWORD'" ; \
	docker exec -i $$DB_CONTAINER psql -U postgres -c "$$sql" 2>&1 > .psql.log | grep -v "already exists" > /dev/null || true ; \
	cat .psql.log ; \
	cat $(LOCAL_INIT_SQL) | docker exec -i $$DB_CONTAINER psql -U $(DB_ADMIN_USER) -d $$PGDATABASE \
	  -vPGUSER=$$PGUSER -vLOCAL_PGUSER=$$LOCAL_PGUSER ; \
	cat .psql.log ; rm .psql.log

# ------------------------------------------------------------------------------

## Remove .done files
clean:
	rm -rf $(OBJECTS)
