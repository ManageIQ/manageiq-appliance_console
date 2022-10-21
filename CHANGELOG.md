# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [8.0.0] - 2022-10-18
### Fixed
- Don't require pressing any key twice for message configuration (#193)

### Added
- Report messaging configuration on summary info page (#190)

### Changed
- Refactor EvmServer operations (#194)
- Only start evmserverd after all application configuration is done (#195)
- **BREAKING** Don't start evmserverd until messaging is configured (#196)
- Simplify messaging options by saving in yml files (#197)

[Unreleased]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v8.0.0...HEAD
[8.0.0]: https://github.com/ManageIQ/manageiq-appliance_console/compare/v7.1.1..v8.0.0
