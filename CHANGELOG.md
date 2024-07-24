# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [9.1.0] - 2024-07-24
### Added
- Add a common method for asking for a password [[#251](https://github.com/ManageIQ/manageiq-appliance_console/pull/251)]
- Add messaging hostname validation [[#254](https://github.com/ManageIQ/manageiq-appliance_console/pull/254)]
- Indicate that messaging persistent disk is optional [[#256](https://github.com/ManageIQ/manageiq-appliance_console/pull/256)]
- Add messaging password validation [[#255](https://github.com/ManageIQ/manageiq-appliance_console/pull/255)]

### Changed
- Deprecate message-server-use-ipaddr option from cli [[#257](https://github.com/ManageIQ/manageiq-appliance_console/pull/257)]

### Fixed
- Add ca-cert to messaging client installed_files [[#258](https://github.com/ManageIQ/manageiq-appliance_console/pull/258)]

## [9.0.3] - 2023-05-06
### Fixed
- Fix missing kafka client ca-cert [[#250]](https://github.com/ManageIQ/manageiq-appliance_console/pull/250)

## [9.0.2] - 2024-05-01
### Fixed
- Bump net-ssh/scp for OpenSSL 3.0 support [[#248]](https://github.com/ManageIQ/manageiq-appliance_console/pull/248)
- Start evmserverd after cli config [[#244]](https://github.com/ManageIQ/manageiq-appliance_console/pull/244)
- Fix missing i18n with appliance_console_cli [[#247]](https://github.com/ManageIQ/manageiq-appliance_console/pull/247)

### Changed
- Update paambaati/codeclimate-action action to v6 [[#249]](https://github.com/ManageIQ/manageiq-appliance_console/pull/249)
- Add renovate.json [[#214]](https://github.com/ManageIQ/manageiq-appliance_console/pull/214)

## [9.0.1] - 2023-03-08
### Fixed
- Enable evmserver after configuring db and messaging [[#239]](https://github.com/ManageIQ/manageiq-appliance_console/pull/239)

## [9.0.0] - 2024-03-05
### Changed
- Update codeclimate channel to the latest in manageiq-style [[#237]](https://github.com/ManageIQ/manageiq-appliance_console/pull/237)

### Removed
- **BREAKING** Remove network configuration from the appliance console [[#238]](https://github.com/ManageIQ/manageiq-appliance_console/pull/238)

## [8.1.0] - 2024-02-07
### Fixed
- Fix sporadic test failure [[#204]](https://github.com/ManageIQ/manageiq-appliance_console/pull/204)
- Remove MIQ specific gem source [[#209]](https://github.com/ManageIQ/manageiq-appliance_console/pull/209)
- Double escape @ in realm to avoid shell interpretation [[#211]](https://github.com/ManageIQ/manageiq-appliance_console/pull/211)
- Move gem name loader to proper namespaced location [[#208]](https://github.com/ManageIQ/manageiq-appliance_console/pull/208)
- Separate kerberos from service principal name and use correctly [[#215]](https://github.com/ManageIQ/manageiq-appliance_console/pull/215)
- Add manageiq user to allowed_uids for sssd [[#220]](https://github.com/ManageIQ/manageiq-appliance_console/pull/220)
- Remove warning about using pg_dump [[#221]](https://github.com/ManageIQ/manageiq-appliance_console/pull/221)
- Fix specs where AwesomeSpawn private interface changed [[#224]](https://github.com/ManageIQ/manageiq-appliance_console/pull/224)
- Change the Name of the CA from something to ApplianceCA [[#228]](https://github.com/ManageIQ/manageiq-appliance_console/pull/228)
- Fix YAML.load_file failing on aliases [[#234]](https://github.com/ManageIQ/manageiq-appliance_console/pull/234)

### Added
- Make backward compatible changes to work with repmgr13 - version 5.2.1 [[#192]](https://github.com/ManageIQ/manageiq-appliance_console/pull/192)
- Support Ruby 3.0 [[#206]](https://github.com/ManageIQ/manageiq-appliance_console/pull/206)
- Support Ruby 3.1 [[#227]](https://github.com/ManageIQ/manageiq-appliance_console/pull/227)
- Allow rails 7 gems in gemspec [[#226]](https://github.com/ManageIQ/manageiq-appliance_console/pull/226)

### Changed
- Update to Highline 2.1.0 [[#201]](https://github.com/ManageIQ/manageiq-appliance_console/pull/201)
- Clean up test output (highline and stdout messages) [[#210]](https://github.com/ManageIQ/manageiq-appliance_console/pull/210)

### Removed
- Drop Ruby 2.7 [[#223]](https://github.com/ManageIQ/manageiq-appliance_console/pull/223)

## [8.0.0] - 2022-10-18
### Fixed
- Don't require pressing any key twice for message configuration [[#193]](https://github.com/ManageIQ/manageiq-appliance_console/pull/193)

### Added
- Report messaging configuration on summary info page [[#190]](https://github.com/ManageIQ/manageiq-appliance_console/pull/190)

### Changed
- **BREAKING** Don't start evmserverd until messaging is configured [[#196]](https://github.com/ManageIQ/manageiq-appliance_console/pull/196)
- Refactor EvmServer operations [[#194]](https://github.com/ManageIQ/manageiq-appliance_console/pull/194)
- Only start evmserverd after all application configuration is done [[#195]](https://github.com/ManageIQ/manageiq-appliance_console/pull/195)
- Simplify messaging options by saving in yml files [[#197]](https://github.com/ManageIQ/manageiq-appliance_console/pull/197)

## [7.2.2] - 2023-06-30
### Fixed
- Fix sporadic test failure [[#204]](https://github.com/ManageIQ/manageiq-appliance_console/pull/204)
- Move gem name loader to proper namespaced location [[#208]](https://github.com/ManageIQ/manageiq-appliance_console/pull/208)
- Separate kerberos from service principal name and use correctly [[#215]](https://github.com/ManageIQ/manageiq-appliance_console/pull/215)

## [7.2.1] - 2023-05-03
### Fixed
- Remove MIQ specific gem source [[#209]](https://github.com/ManageIQ/manageiq-appliance_console/pull/209)
- Double escape @ in realm to avoid shell interpretation [[#211]](https://github.com/ManageIQ/manageiq-appliance_console/pull/211)

## [7.2.0] - 2022-11-01
### Added
- Make backward compatible changes to work with repmgr13 - version 5.2.1

### Fixed
- Don't require user to press_any_key twice after successful messaging configuration
- Swap "localhost" to 127.0.0.1 in Messaging server configuration
- Simplify messaging options by saving in yml files

## [7.1.1] - 2022-09-02
### Fixed
- 6.1 configurations has symbol keys, [] deprecated, use configs_for [[#189]](https://github.com/ManageIQ/manageiq-appliance_console/pull/189)

## [7.1.0] - 2022-08-12
### Changed
- Upgrade to Rails 6.1

## [7.0.6] - 2022-07-14
### Changed
- Fix issue where region env var was not passed as a String [[#185]](https://github.com/ManageIQ/manageiq-appliance_console/pull/185)

## [7.0.5] - 2022-07-13
### Changed
- Fixed calls to `rake` command [[#184]](https://github.com/ManageIQ/manageiq-appliance_console/pull/184)

## [7.0.4] - 2022-07-12
### Changed
- Pass region as an environment variable [[#182]](https://github.com/ManageIQ/manageiq-appliance_console/pull/182)

## [7.0.3] - 2022-02-22
### Changed
- Check if kafka is installed before allowing messaging changes [[#180]](https://github.com/ManageIQ/manageiq-appliance_console/pull/180)

## [7.0.2] - 2021-11-03
### Changed
- Loosen manageiq-password to < 2 [[#175]](https://github.com/ManageIQ/manageiq-appliance_console/pull/175)

## [7.0.1] - 2021-09-15
### Changed
- Move in db_connections code from core
- We were locked down to activerecord/activesupport ~> 6.0.3.5 which didn't allow us to update to 6.0.4.1, loosen the dependency

## [7.0.0] - 2021-08-04
### Fixed
- Chown database.yml as manageiq:manageiq [[#165]](https://github.com/ManageIQ/manageiq-appliance_console/pull/165)
- Create /opt/kafka/config/keystore directory [[#170]](https://github.com/ManageIQ/manageiq-appliance_console/pull/170)
- Add missing parse_errors() method [[#169]](https://github.com/ManageIQ/manageiq-appliance_console/pull/169)

### Added
- Add database dump/backup/restore to CLI [[#161]](https://github.com/ManageIQ/manageiq-appliance_console/pull/161)
- Use PostgresAdmin directly for DB backups [[#160]](https://github.com/ManageIQ/manageiq-appliance_console/pull/160)

## [6.1.1] - 2021-09-15
### Changed
- Upgrade to rails 6.0.4.1 [[#173]](https://github.com/ManageIQ/manageiq-appliance_console/pull/173)

## [6.1.0] - 2021-03-30
### Added
- Support a configuring the kafka server with the current IPAddr [[#159]](https://github.com/ManageIQ/manageiq-appliance_console/pull/159)
- Support moving Kafka Persistent data to a dedicated disk [[#158]](https://github.com/ManageIQ/manageiq-appliance_console/pull/158)
- Inject postgres admin into the appliance console [[#157]](https://github.com/ManageIQ/manageiq-appliance_console/pull/157)
- [Utilities] Add #disk_usage [[#155]](https://github.com/ManageIQ/manageiq-appliance_console/pull/155)
- When configuring the kafka client disable the server [[#154]](https://github.com/ManageIQ/manageiq-appliance_console/pull/154)
- Pass password to the keytool command using stdin [[#152]](https://github.com/ManageIQ/manageiq-appliance_console/pull/152)
- Support configuring Kafka through the CLI [[#151]](https://github.com/ManageIQ/manageiq-appliance_console/pull/151)
- Unify kafka client setup [[#149]](https://github.com/ManageIQ/manageiq-appliance_console/pull/149)
- use attr_reader only for password [[#148]](https://github.com/ManageIQ/manageiq-appliance_console/pull/148)
- remove duplicate class attr writer [[#145]](https://github.com/ManageIQ/manageiq-appliance_console/pull/145)
- Toggle Settings.prototype.messaging_type for Kafka support [[#137]](https://github.com/ManageIQ/manageiq-appliance_console/pull/137)
- Initial commit of kafka server configuration [[#130]](https://github.com/ManageIQ/manageiq-appliance_console/pull/130)

### Fixed
- Fix Hakiri errors on activesupport/activerecord [[#156]](https://github.com/ManageIQ/manageiq-appliance_console/pull/156)
- Fix MAC test failures [[#150]](https://github.com/ManageIQ/manageiq-appliance_console/pull/150)

## [6.0.0] - 2020-11-11
### Added
- Try to fetch introspect endpoint from the provider metadata [[#121]](https://github.com/ManageIQ/manageiq-appliance_console/pull/121)

### Removed
- **BREAKING** Remove rbnacl-libsodium [[#134]](https://github.com/ManageIQ/manageiq-appliance_console/pull/134)

  rbnacl-libsodium is discontinued and it is preferable to use the
  system package instead.  Due to this, we are releasing this as a major
  version, so that systems don't accidentally pull in a patch or minor
  release which would then require system-level changes to install the
  system package.

## [5.5.0] - 2020-05-12
### Added
- Add support for the oidc introspection endpoint [[#117]](https://github.com/ManageIQ/manageiq-appliance_console/pull/117)

### Changed
- Rename "Configure Application Database Failover Monitor" [[#116]](https://github.com/ManageIQ/manageiq-appliance_console/pull/116)

## [5.4.0] - 2020-04-14
### Added
- Support for configuring an external messaging system [[#114]](https://github.com/ManageIQ/manageiq-appliance_console/pull/114)

## [5.3.3] - 2020-04-02
### Added
- Add necessary dependencies to support ssh with ed25519 cipher [[#113]](https://github.com/ManageIQ/manageiq-appliance_console/pull/113)
- Add missing net-scp runtime dependency [[#113]](https://github.com/ManageIQ/manageiq-appliance_console/pull/113)

## [5.3.2] - 2020-03-05
### Changed
- Use LinuxAdmin::Service#start with enable set to true

## [5.3.1] - 2020-01-16
### Changed
- Deduplicate the SCAP_RULES_DIR constan
- Update hostname regex to allow starting with digit
- Use the regex to validate hostnames when we set them

## [5.3.0] - 2019-12-12

## [5.2.0] - 2019-12-06

## [5.1.0] - 2019-11-22
### Changed
- Adding support for configuring Appliance SAML Authentication via the CLI

## [5.0.3] - 2019-09-19
### Changed
- Ensure that the CLI exits non-zero on database configuration error

## [5.0.2] - 2019-08-14
### Changed
- Restore the selinux context for the standby data directory [[#96]](https://github.com/ManageIQ/manageiq-appliance_console/pull/96)

## [5.0.1] - 2019-07-08
### Changed
- Remove unrecommended mount option "nobarrier" [[#95]](https://github.com/ManageIQ/manageiq-appliance_console/pull/95)
- Fix multiple issues with logfile disk configuration [[#93]](https://github.com/ManageIQ/manageiq-appliance_console/pull/93)

## [5.0.0] - 2019-06-10
### Changed
- Remove PG certificate handling [[#88]](https://github.com/ManageIQ/manageiq-appliance_console/pull/88)
- Don't attempt a database restore if evmserverd is running [[#91]](https://github.com/ManageIQ/manageiq-appliance_console/pull/91)

## [4.0.2] - 2019-03-27
### Changed
- Remove references to MiqPassword

## [4.0.1] - 2019-03-14
### Changed
- Fix permissions on PG user home directory after disk mount

## [4.0.0] - 2019-03-12
### Changed
- **BREAKING** Upgrade to Postgres 10
- Handle existing certs and support rerun of cert generation
- Enable certmonger to restart on reboot
- Switch to optimist gem

## [3.3.3] - 2019-09-19

## [3.3.2] - 2019-07-09

## [3.3.1] - 2019-02-14

## [3.3.0] - 2018-11-05

## [3.2.0] - 2018-08-23

## [3.1.0] - 2018-08-16

## [3.0.0] - 2018-08-01

## [2.0.3] - 2018-05-03

## [2.0.2] - 2018-05-02

## [2.0.1] - 2018-04-25

## [2.0.0] - 2018-03-09

## [1.2.4] - 2018-01-18

## [1.2.3] - 2018-01-04

## [1.2.2] - 2017-12-20

## [1.2.1] - 2017-12-19

## [1.2.0] - 2017-12-14

## [1.1.0] - 2017-12-11

## [1.0.1] - 2017-10-19

## [1.0.0] - 2017-10-19

[Unreleased]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v9.1.0...HEAD
[9.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v9.0.3...v9.1.0
[9.0.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v9.0.2...v9.0.3
[9.0.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v9.0.1...v9.0.2
[9.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v9.0.0...v9.0.1
[9.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v8.1.0...v9.0.0
[8.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v8.0.0...v8.1.0
[8.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.2.2...v8.0.0
[7.2.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.2.1...v7.2.2
[7.2.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.2.0...v7.2.1
[7.2.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.1.1...v7.2.0
[7.1.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.1.0...v7.1.1
[7.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.6...v7.1.0
[7.0.6]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.5...v7.0.6
[7.0.5]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.4...v7.0.5
[7.0.4]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.3...v7.0.4
[7.0.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.2...v7.0.3
[7.0.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.1...v7.0.2
[7.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.0.0...v7.0.1
[7.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v6.1.1...v7.0.0
[6.1.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v6.1.0...v6.1.1
[6.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v6.0.0...v6.1.0
[6.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.5.0...v6.0.0
[5.5.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.4.0...v5.5.0
[5.4.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.3.3...v5.4.0
[5.3.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.3.2...v5.3.3
[5.3.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.3.1...v5.3.2
[5.3.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.3.0...v5.3.1
[5.3.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.2.0...v5.3.0
[5.2.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.1.0...v5.2.0
[5.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.0.3...v5.1.0
[5.0.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.0.2...v5.0.3
[5.0.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.0.1...v5.0.2
[5.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v4.0.2...v5.0.0
[4.0.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v4.0.1...v4.0.2
[4.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.3.3...v4.0.0
[3.3.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.2.2...v3.3.3
[3.3.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.3.1...v3.3.2
[3.3.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.3.0...v3.3.1
[3.3.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v2.0.3...v3.0.0
[2.0.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.2.4...v2.0.0
[1.2.4]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/tree/v1.0.0
