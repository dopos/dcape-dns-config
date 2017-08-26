# dcape-dns-config
Config for dcape based powerdns server

This project contains Makefile and sample sql zone definition for loading zones into PowerDNS server.

## Requirements

* [dcape](https://github.com/TenderPro/dcape) installed on remote host with pdns and gitea running

## Usage

* fork this project into your dcape gitea
* in gitea project settings setup hook for server where powerdns service running
* clone project locally from gitea
* add your zones .sql by example from domain.sql.sample
* make `git push` and change project env in dcape cis config frontend
* make `git push` again and see updated dns zones


## TODO

* [ ] Zone rectification SQL
