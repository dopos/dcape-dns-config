# dcape-dns-config

Config for dcape based powerdns server

This project contains Makefile and sample sql zone definition for loading zones into PowerDNS server.

## Requirements

* linux 64bit (git, make, wget, gawk, openssl)
* [docker](http://docker.io)
* [dcape](https://github.com/dopos/dcape)
* Git service ([github](https://github.com), [gitea](https://gitea.io) or [gogs](https://gogs.io))

## Usage

* fork this project into your dcape gitea
* in gitea project settings setup hook for server where powerdns service running
* clone project locally from gitea
* add your zones .sql by example from domain.sql.sample
* make `git push` and change project env in dcape cis config frontend
* make `git push` again and see updated dns zones


## TODO

* [ ] Zone rectification SQL

## License

The MIT License (MIT), see [LICENSE](LICENSE).

Copyright (c) 2017-2024 Aleksei Kovrizhkin <lekovr+dopos@gmail.com>
