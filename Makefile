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

#- Postgresql container name (access via docker)
PG_CONTAINER ?= dcape-db-1

#- PowerDNS DB user name
PGUSER       ?= pdns

#- PowerDNS DB name
PGDATABASE   ?= pdns

#- Used ONLY for direct DB access without docker (update-direct)
PGPASSWORD   ?=

#- ACME zone suffix
ACME_DOMAIN  ?=

#- This NS hostname for use in all SOA
NSERVER      ?=

# ------------------------------------------------------------------------------
-include $(CFG).bak
export

-include $(CFG)
export

# ------------------------------------------------------------------------------
# dcape v1 comparibility

start-hook: update

stop:

# ------------------------------------------------------------------------------
# Find and include DCAPE_ROOT/Makefile
DCAPE_COMPOSE   ?= dcape-compose
DCAPE_ROOT      ?= $(shell docker inspect -f "{{.Config.Labels.dcape_root}}" $(DCAPE_COMPOSE))

ifeq ($(shell test -e $(DCAPE_ROOT)/Makefile.app && echo -n yes),yes)
  include $(DCAPE_ROOT)/Makefile.app
else
  include /opt/dcape/Makefile.app
endif

# ------------------------------------------------------------------------------
update: $(OBJECTS)

%.done: %.sql
	@echo "*** $< ***"
	@csum=$$(md5sum $< | sed 's/ .*//') ; \
	  cat $< | docker exec -i $$PG_CONTAINER psql -U $$PGUSER -d $$PGDATABASE -vcsum=$$csum -vACME_DOMAIN=$(ACME_DOMAIN) -vNSERVER=$(NSERVER) > $@

## Load updated zone files via psql connection
update-direct: $(CFG) $(OBJECTSDIRECT)

%.direct: %.sql
	@echo "*** $< ***"
	@source $(CFG) && cat $< | PGPASSWORD=$$PGPASSWORD psql -h localhost -U $$PGUSER > $@

# ------------------------------------------------------------------------------

## Remove .done files
clean:
	rm -rf $(OBJECTS)
