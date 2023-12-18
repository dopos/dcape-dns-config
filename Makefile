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
ACME_DOMAIN     ?=

#- This NS hostname for use in all SOA
NSERVER         ?=

#- db container
DB_CONTAINER    ?= #

#- PowerDNS DB user name
PGUSER          ?= pdns

#- PowerDNS DB name
PGDATABASE      ?= pdns

#- Used ONLY for direct DB access without docker (update-direct)
PGPASSWORD      ?=
#- Used ONLY for direct DB access without docker (update-direct)
DB_PORT_LOCAL   ?=

USE_DCAPE_DC    := no

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
	  cat $< | docker exec -i $$DB_CONTAINER psql -U $$PGUSER -d $$PGDATABASE -vcsum=$$csum -vACME_DOMAIN=$(ACME_DOMAIN) -vNSERVER=$(NSERVER) > $@

## Load updated zone files via psql connection
update-direct: $(CFG) $(OBJECTSDIRECT)

%.direct: %.sql
	@echo "*** $< ***"
	@source $(CFG) && cat $< | PGPASSWORD=$${PGPASSWORD:?Must be set} psql -h localhost -U $$PGUSER -p $${DB_PORT_LOCAL:?Must be set} > $@

# ------------------------------------------------------------------------------

## Remove .done files
clean:
	rm -rf $(OBJECTS)
